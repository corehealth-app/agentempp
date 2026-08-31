#!/usr/bin/env node

import { createHash, createPrivateKey, createPublicKey, sign as signSignature, verify as verifySignature } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { constants as FS_CONSTANTS } from 'node:fs';
import {
  chmod,
  link,
  lstat,
  mkdir,
  mkdtemp,
  open,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { homedir, tmpdir, userInfo } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const AUTHORITY_PARENT = '456b4643d1a310bc88458a28a9a62a16dde2e1c8';
export const AUTHORITY_SUBJECT = 'build(ops): reconcile staging env receipt for CI-3 bridge';
const CI3_PARENT = '277873755bf29771a10b5f362b522c2e6a6c21d6';
const CI3_SUBJECT = 'feat(ios): connect Today to authenticated staging';
const BUNDLE_ID = 'com.bodyflow.app';
const SSH_PATH = '/usr/bin/ssh';
const INSTALL_PATH = '/usr/bin/install';
const XCRUN_PATH = '/usr/bin/xcrun';

export const TERMINAL_SCAN_IDS = Object.freeze([
  'argv', 'history', 'terminal-log', 'attachment', 'xcresult', 'runtime',
]);

export const SCAN_SURFACE_CONTRACTS = Object.freeze(Object.fromEntries([
  ['argv', 'jsonl', 'controller-invocation-argv'],
  ['history', 'utf8-lines', 'controller-command-history'],
  ['terminal-log', 'jsonl', 'controller-terminal-transcript'],
  ['attachment', 'jsonl', 'controller-evidence-attachments'],
  ['xcresult', 'json', 'simulator-test-result'],
  ['runtime', 'jsonl', 'controller-runtime-environment'],
].map(([id, format, sourceRole]) => [id, Object.freeze({
  id, format, source_role: sourceRole,
  source_semantics: id,
  fixed_source_relative_path: `final-sources/${id}.surface`,
  required_state: id === 'xcresult' ? 'PRESENT_OR_PROVEN_ABSENT' : 'REQUIRED_PRESENT',
  collector_version: `ci3-${id}-collector-v1`,
  fixed_relative_path: `scan-surfaces/${id}.surface`,
})])));

export const PRESERVED_CI3_PATHS = Object.freeze([
  'apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift',
  'apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift',
  'apps/ios/BodyFlow/BodyFlow/Core/Configuration/MobileStagingConfiguration.swift',
  'apps/ios/BodyFlow/BodyFlowTests/CI3StagingLaunchConfigurationTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/MobileStagingConfigurationTests.swift',
]);

export const CONTINUATION_ALLOWLIST_PATHS = Object.freeze([
  'apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift',
  'apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift',
  'apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift',
  'apps/ios/BodyFlow/BodyFlow/Core/Configuration/MobileStagingConfiguration.swift',
  'apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIEnvelope.swift',
  'apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransport.swift',
  'apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransportError.swift',
  'apps/ios/BodyFlow/BodyFlow/Core/Today/MobileAPITodayProvider.swift',
  'apps/ios/BodyFlow/BodyFlow/Core/Today/TodayModels.swift',
  'apps/ios/BodyFlow/BodyFlow/Features/Today/TodayViewModel.swift',
  'apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift',
  'apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings',
  'apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/CI3StagingLaunchConfigurationTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/MobileStagingConfigurationTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/MobileAPITransportTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/MobileAPITodayProviderTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/TodayContractTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/TodayViewModelTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/TodayPresentationTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/LocalizationContractTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/CI3StagingIntegrationTests.swift',
  'apps/ios/BodyFlow/BodyFlowUITests/CI3TodayStagingUITests.swift',
]);

export const CONTINUATION_ALLOWLIST_SHA256 = sha256(canonicalJson(CONTINUATION_ALLOWLIST_PATHS));

const simulatorRolePrefix = (phase) => `simulator-phase-${phase.toLowerCase().replaceAll('_', '-')}`;
export const SIMULATOR_EVIDENCE_ROLES = Object.freeze([
  'SELECT_DEVICE', 'RESOLVE_CONTAINER', 'INSTALL_PROBE', 'LAUNCH_PROBE',
  'ACK_PROBE', 'REMOVE_PROBE', 'REOBSERVE',
].flatMap((phase) => ['claim', 'receipt', 'result'].map((kind) => `${simulatorRolePrefix(phase)}-${kind}`)));

export const CONTROLLER_EVIDENCE_PHASES = Object.freeze([
  'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
  'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
]);
export const CONTROLLER_EVIDENCE_ROLES = Object.freeze(CONTROLLER_EVIDENCE_PHASES.flatMap((phase) => {
  const prefix = `controller-phase-${phase.toLowerCase().replaceAll('_', '-')}`;
  return ['claim', 'receipt', 'result'].map((kind) => `${prefix}-${kind}`);
}));

export const TERMINAL_MANIFEST_EVIDENCE_ROLES = Object.freeze([
  'authority-manifest', 'launch-attestation', 'bootstrap-claim',
  'receipt-read-claim', 'receipt-read-result', 'config-read-claim', 'config-read-result',
  'credential-read-claim', 'credential-read-result', 'remote-receipt', 'local-receipt',
  'ssh-provenance', 'simulator-gate', 'simulator-install', 'input-manifest',
  'terminal-receipt', 'controller-durable-state-root', 'writer-source',
  'operation-authority-root', 'vps-pass-root', 'vps-issuer-authority-root',
  'human-authorization-root', 'publisher-input-manifest-root',
  'ssh-trust-descriptor', 'ssh-public-key', 'ssh-public-key-fingerprint',
  ...SIMULATOR_EVIDENCE_ROLES, ...CONTROLLER_EVIDENCE_ROLES,
]);

const TERMINAL_ROOT_EVIDENCE_ROLES = Object.freeze(new Set([
  'operation-authority-root', 'vps-pass-root', 'vps-issuer-authority-root',
  'human-authorization-root', 'publisher-input-manifest-root',
  'ssh-trust-descriptor', 'ssh-public-key',
]));

export const FULL_PROTOCOL_E2E_SCENARIOS = Object.freeze([
  'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
  'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
  'INVOKE_WRITER', 'VERIFY_ANCHOR',
].flatMap((phase) => [
  'before-claim', 'after-claim', 'after-effect', 'after-receipt', 'after-result', 'after-event',
].map((boundary) => Object.freeze({ id: `${phase}:${boundary}`, phase, boundary }))));

export const TERMINAL_SETTLEMENT_PHASES = Object.freeze(['INVOKE_WRITER', 'VERIFY_ANCHOR']);

export const TERMINAL_FINAL_SURFACE_ROLES = Object.freeze([
  'process-argv', 'controller-journal', 'controller-stdout', 'controller-stderr',
  'terminal-attachments', 'simulator-xcresult', 'runtime-environment',
  'writer-output', 'terminal-settlement', 'complete-result',
]);

export const IMPORTANT_FINDINGS = Object.freeze([
  { id: 'RA1-I-5', test: 'terminal chain requires all six claimed scans', receipt_field: 'scan_receipts', anchor_field: 'scan_receipts' },
  { id: 'A4-I-1', test: 'simulator phases emit durable physical receipts', receipt_field: 'simulator_phase_receipts', anchor_field: 'simulator_gate_sha256' },
  { id: 'A4-I-3', test: 'local publication promotes one staged directory', receipt_field: 'local_publication_result_sha256', anchor_field: 'local_bundle_sha256' },
  { id: 'A5-I-1', test: 'captured remote bytes remain on one descriptor', receipt_field: 'capture_identity_sha256', anchor_field: 'claim_result_chain_sha256' },
  { id: 'A5-I-2', test: 'Git snapshot binds executed generation', receipt_field: 'generator_blob_oid', anchor_field: 'components.generator' },
  { id: 'RA0-I-4', test: 'every physical phase has claim and result', receipt_field: 'phase_result_hashes', anchor_field: 'claim_result_chain_sha256' },
  { id: 'RA0-I-7', test: 'six scanners expose independent class counters', receipt_field: 'scan_counters', anchor_field: 'scan_receipts' },
  { id: 'R2-I-2', test: 'writer semantically recomputes evidence roots', receipt_field: 'semantic_roots', anchor_field: 'semantic_roots' },
  { id: 'R5-I-1', test: 'descriptor-first no-follow bundle publication', receipt_field: 'local_bundle_identity_sha256', anchor_field: 'local_bundle_sha256' },
  { id: 'R5-I-2', test: 'native ssh-G descriptor is complete and ordered', receipt_field: 'ssh_trust_descriptor_sha256', anchor_field: 'ssh_provenance_sha256' },
  { id: 'R5-I-3', test: 'remote read grammar has no reopened filter', receipt_field: 'remote_command_sha256', anchor_field: 'claim_result_chain_sha256' },
  { id: 'RA-FINAL-I-1', test: 'Git-bound launcher is reachable', receipt_field: 'launcher_blob_oid', anchor_field: 'components.launcher' },
  { id: 'RA-FINAL-I-2', test: 'exact-existing requires original full claim', receipt_field: 'bootstrap_claim_sha256', anchor_field: 'claim_result_chain_sha256' },
  { id: 'RA-FINAL-I-3', test: 'six closed scans reject rewrite', receipt_field: 'scan_receipts', anchor_field: 'scan_receipts' },
  { id: 'RA-FINAL-I-4', test: 'terminal anchor closes all generations', receipt_field: 'terminal_generation_id', anchor_field: 'generations' },
  { id: 'RA-FINAL-I-5', test: 'privileged authority is external and hash-bound', receipt_field: 'writer_authority_path_sha256', anchor_field: 'privileged_claim_sha256' },
  { id: 'RA-FINAL-I-6', test: 'test and finding counts are current', receipt_field: 'important_finding_ids', anchor_field: 'important_finding_ids' },
  { id: 'RB-FINAL-I-1', test: 'launcher executes committed controller snapshot', receipt_field: 'controller_blob_oid', anchor_field: 'components.controller' },
  { id: 'RB-FINAL-I-2', test: 'Mac controller runs one closed state machine', receipt_field: 'controller_generation_id', anchor_field: 'generations.controller' },
  { id: 'RB-FINAL-I-3', test: 'native ssh-G complete ordered policy', receipt_field: 'ssh_provenance_sha256', anchor_field: 'ssh_provenance_sha256' },
  { id: 'RB-FINAL-I-4', test: 'simulator seven-phase early gate', receipt_field: 'simulator_gate_sha256', anchor_field: 'simulator_gate_sha256' },
  { id: 'RB-FINAL-I-5', test: 'scanner closes exact operational surfaces', receipt_field: 'scan_ids', anchor_field: 'scan_receipts' },
  { id: 'RB-FINAL-I-6', test: 'writer requires privileged original claim', receipt_field: 'writer_claim_sha256', anchor_field: 'privileged_claim_sha256' },
  { id: 'RB-FINAL-I-7', test: 'install uses frozen binary and fd readback', receipt_field: 'install_receipt_sha256', anchor_field: 'simulator_install_sha256' },
]);

export const AUTHORITY_PATHS = Object.freeze([
  'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md',
  'docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md',
  'docs/superpowers/evidence/2026-08-31-ci3-bridge-git-blob-reader-stop-and-authority.md',
  'docs/superpowers/evidence/2026-08-31-ci3-env-receipt-reconciliation-authority.md',
  'docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md',
  'scripts/ci3/create-ios-staging-bridge-config.mjs',
  'scripts/ci3/create-ios-staging-bridge-config.test.mjs',
  'scripts/ci3/ci3-bridge-controller.mjs',
  'scripts/ci3/ci3-bridge-controller.test.mjs',
  'scripts/ci3/ci3-bridge-launcher.zsh',
  'scripts/ci3/ci3-bridge-launcher.test.mjs',
  'scripts/ci3/ci3-terminal-anchor-writer.swift',
  'scripts/ci3/ci3-terminal-anchor-writer.test.mjs',
]);

export class ControllerError extends Error {
  constructor(code) {
    super(code);
    this.name = 'ControllerError';
    this.code = code;
  }
}

function fail(code) {
  throw new ControllerError(code);
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

function isSha(value, lengths = [64]) {
  return typeof value === 'string' && lengths.includes(value.length) && /^[a-f0-9]+$/.test(value);
}

function requireSha(value, code, lengths = [64]) {
  if (!isSha(value, lengths)) fail(code);
}

export function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export function canonicalJson(value) {
  const normalize = (candidate) => {
    if (Array.isArray(candidate)) return candidate.map(normalize);
    if (isPlainObject(candidate)) return Object.fromEntries(Object.keys(candidate).sort().map((key) => [key, normalize(candidate[key])]));
    return candidate;
  };
  return Buffer.from(`${JSON.stringify(normalize(value))}\n`);
}

export function parseControllerMode(argv) {
  const allowed = new Set([
    '--self-test', '--terminalize-tail', 'plan', 'verify-simulator', 'verify-ssh', 'fetch',
    'install-simulator', 'scan', 'write-terminal-anchor', 'resume', 'status',
    'publish-vps-operation-authority-pass', 'publish-operation-authority',
    'publish-privileged-writer-authority',
  ]);
  if (!Array.isArray(argv) || argv.length !== 1 || !allowed.has(argv[0])) fail('MODE_INVALID');
  return argv[0];
}

export function validatePreservedCi3Paths(paths) {
  if (!Array.isArray(paths) || !canonicalJson(paths).equals(canonicalJson(PRESERVED_CI3_PATHS))) fail('OPERATION_AUTHORITY');
  return true;
}

export function validateLaunchAttestation(attestation) {
  const code = 'LAUNCHER_REQUIRED';
  exactKeys(attestation, [
    'authority_manifest_sha256', 'authority_parent', 'authority_sha',
    'authority_subject_sha256', 'authority_tree', 'components', 'purpose',
    'raw_values', 'schema_version', 'tools',
  ], code);
  if (attestation.schema_version !== 1
      || attestation.purpose !== 'CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2'
      || attestation.raw_values !== false) fail(code);
  requireSha(attestation.authority_sha, code, [40]);
  requireSha(attestation.authority_parent, code, [40]);
  requireSha(attestation.authority_tree, code, [40]);
  requireSha(attestation.authority_subject_sha256, code);
  requireSha(attestation.authority_manifest_sha256, code);
  validateComponents(attestation.components, code);
  exactKeys(attestation.tools, ['node', 'ssh', 'swiftc', 'xcodebuild'], code);
  for (const identity of Object.values(attestation.tools)) {
    exactKeys(identity, ['binary_sha256', 'path_sha256', 'version_sha256'], code);
    requireSha(identity.binary_sha256, code);
    requireSha(identity.path_sha256, code);
    requireSha(identity.version_sha256, code);
  }
  return true;
}

export function validateGenerationId(value) {
  if (!/^(remote|controller|simulator|terminal)-[a-f0-9]{64}$/.test(value ?? '')) fail('GENERATION_ID');
  return true;
}

const COMPONENT_PATHS = Object.freeze({
  generator: 'scripts/ci3/create-ios-staging-bridge-config.mjs',
  controller: 'scripts/ci3/ci3-bridge-controller.mjs',
  launcher: 'scripts/ci3/ci3-bridge-launcher.zsh',
  writer: 'scripts/ci3/ci3-terminal-anchor-writer.swift',
});

export function validateAuthorityManifest({ entries, components }) {
  const code = 'AUTHORITY_MANIFEST';
  if (!Array.isArray(entries) || entries.length !== AUTHORITY_PATHS.length) fail(code);
  const seen = new Set();
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    exactKeys(entry, ['blob_oid', 'path', 'sha256'], code);
    if (entry.path !== AUTHORITY_PATHS[index] || seen.has(entry.path)) fail(code);
    requireSha(entry.blob_oid, code, [40]);
    requireSha(entry.sha256, code);
    seen.add(entry.path);
  }
  exactKeys(components, ['controller', 'generator', 'launcher', 'writer'], code);
  for (const [name, expectedPath] of Object.entries(COMPONENT_PATHS)) {
    exactKeys(components[name], ['blob_oid', 'path', 'sha256'], code);
    const entry = entries.find(({ path: candidate }) => candidate === expectedPath);
    if (!entry || components[name].path !== expectedPath || components[name].blob_oid !== entry.blob_oid || components[name].sha256 !== entry.sha256) fail(code);
  }
  return true;
}

export function parseAuthorityManifestBytes(bytes, components) {
  const code = 'AUTHORITY_MANIFEST';
  const text = Buffer.from(bytes).toString('utf8');
  if (!text.endsWith('\n') || text.includes('\r') || text.includes('\0')) fail(code);
  const lines = text.slice(0, -1).split('\n');
  if (lines.length !== AUTHORITY_PATHS.length) fail(code);
  const entries = lines.map((line, index) => {
    const parts = line.split(' ');
    if (parts.length !== 3 || parts[0] !== AUTHORITY_PATHS[index]
        || !isSha(parts[1], [40]) || !isSha(parts[2])) fail(code);
    return { path: parts[0], blob_oid: parts[1], sha256: parts[2] };
  });
  validateAuthorityManifest({ entries, components });
  return {
    schema_version: 1, purpose: 'CI3_LITERAL_AUTHORITY_MANIFEST_V1',
    source_sha256: sha256(Buffer.from(bytes)), entries, components, raw_values: false,
  };
}

function validateComponents(components, code) {
  exactKeys(components, ['controller', 'generator', 'launcher', 'writer'], code);
  for (const [name, expectedPath] of Object.entries(COMPONENT_PATHS)) {
    exactKeys(components[name], ['blob_oid', 'path', 'sha256'], code);
    if (components[name].path !== expectedPath) fail(code);
    requireSha(components[name].blob_oid, code, [40]);
    requireSha(components[name].sha256, code);
  }
}

export function buildBootstrapClaim(context) {
  const code = 'BOOTSTRAP_CLAIM';
  const { authority, generations, remote, simulator_gate_sha256: simulatorGateSha256, ssh } = context ?? {};
  if (!isSha(authority?.commit, [40]) || authority.parent !== AUTHORITY_PARENT || authority.subject !== AUTHORITY_SUBJECT) fail(code);
  requireSha(authority.manifest_sha256, code);
  validateComponents(authority.components, code);
  for (const generation of Object.values(generations ?? {})) validateGenerationId(generation);
  for (const value of [remote?.bundle_path_sha256, remote?.receipt_path_sha256, simulatorGateSha256, ssh?.executable_sha256, ssh?.effective_config_sha256, ssh?.trust_descriptor_sha256]) requireSha(value, code);
  return {
    schema_version: 1,
    purpose: 'CI3_MAC_BRIDGE_BOOTSTRAP_CLAIM_V1',
    authority_sha: authority.commit,
    authority_manifest_sha256: authority.manifest_sha256,
    components: structuredClone(authority.components),
    remote_bundle_path_sha256: remote.bundle_path_sha256,
    remote_receipt_path_sha256: remote.receipt_path_sha256,
    ssh_executable_sha256: ssh.executable_sha256,
    ssh_code_signature_sha256: ssh.code_signature_sha256,
    ssh_effective_config_sha256: ssh.effective_config_sha256,
    ssh_trust_descriptor_sha256: ssh.trust_descriptor_sha256,
    simulator_gate_sha256: simulatorGateSha256,
    remote_generation_id: generations.remote,
    controller_generation_id: generations.controller,
    simulator_generation_id: generations.simulator,
    terminal_generation_id: generations.terminal,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
}

export function validateBootstrapClaim(claim, context) {
  const expected = buildBootstrapClaim(context);
  if (!Buffer.from(canonicalJson(claim)).equals(canonicalJson(expected))) fail('BOOTSTRAP_CLAIM');
  return true;
}

export function buildReadClaim({ kind, bootstrapClaimSha256, expectedPathSha256, expectedSha256, remoteGenerationId, ssh } = {}) {
  const code = 'READ_CLAIM';
  if (!['receipt', 'config', 'credential'].includes(kind)) fail(code);
  for (const value of [bootstrapClaimSha256, expectedPathSha256, expectedSha256, ssh?.executable_sha256, ssh?.effective_config_sha256, ssh?.trust_descriptor_sha256]) requireSha(value, code);
  if (kind === 'receipt') {
    if (remoteGenerationId !== null) fail(code);
  } else {
    try { validateGenerationId(remoteGenerationId); } catch { fail(code); }
  }
  return {
    schema_version: 1,
    purpose: 'CI3_MAC_BRIDGE_READ_CLAIM_V1',
    kind,
    bootstrap_claim_sha256: bootstrapClaimSha256,
    expected_path_sha256: expectedPathSha256,
    expected_sha256: expectedSha256,
    remote_generation_id: remoteGenerationId,
    ssh_executable_sha256: ssh.executable_sha256,
    ssh_effective_config_sha256: ssh.effective_config_sha256,
    ssh_trust_descriptor_sha256: ssh.trust_descriptor_sha256,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
}

export function buildReadResult({
  kind, claimSha256, captureSha256, captureIdentitySha256, remoteCommandSha256,
  descriptorRead, bytes, exit, stderrClass, startedAt, finishedAt,
  sshEffectiveConfigSha256, sshTrustDescriptorSha256, remoteGenerationId,
}) {
  const code = 'READ_RESULT';
  if (!['receipt', 'config', 'credential'].includes(kind)) fail(code);
  for (const value of [claimSha256, captureSha256, captureIdentitySha256, remoteCommandSha256, sshEffectiveConfigSha256, sshTrustDescriptorSha256]) requireSha(value, code);
  validateGenerationId(remoteGenerationId);
  if (descriptorRead !== true || !Number.isInteger(bytes) || bytes < 0 || exit !== 0 || !/^[A-Z0-9_]+$/.test(stderrClass ?? '')) fail(code);
  if (!Number.isFinite(Date.parse(startedAt)) || !Number.isFinite(Date.parse(finishedAt)) || Date.parse(finishedAt) < Date.parse(startedAt)) fail(code);
  return {
    schema_version: 1,
    purpose: 'CI3_MAC_BRIDGE_READ_RESULT_V1',
    kind,
    claim_sha256: claimSha256,
    capture_sha256: captureSha256,
    capture_identity_sha256: captureIdentitySha256,
    remote_command_sha256: remoteCommandSha256,
    descriptor_read: true,
    bytes,
    exit,
    stderr_class: stderrClass,
    started_at: startedAt,
    finished_at: finishedAt,
    ssh_effective_config_sha256: sshEffectiveConfigSha256,
    ssh_trust_descriptor_sha256: sshTrustDescriptorSha256,
    remote_generation_id: remoteGenerationId,
    raw_values: false,
  };
}

export function validateRemoteCaptureReceipt(receipt, { kind, claim, captureSha256, captureIdentitySha256, remoteCommandSha256 } = {}) {
  const code = 'REMOTE_CAPTURE_RECEIPT';
  exactKeys(receipt, [
    'bytes', 'capture_identity_sha256', 'capture_sha256', 'claim_sha256',
    'descriptor_read', 'finished_at', 'kind', 'purpose', 'raw_values',
    'remote_command_sha256', 'schema_version', 'started_at',
  ], code);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_REMOTE_CAPTURE_RECEIPT_V1'
      || receipt.kind !== kind || receipt.claim_sha256 !== sha256(canonicalJson(claim))
      || receipt.capture_sha256 !== captureSha256
      || receipt.capture_identity_sha256 !== captureIdentitySha256
      || receipt.remote_command_sha256 !== remoteCommandSha256
      || receipt.descriptor_read !== true || receipt.raw_values !== false
      || !Number.isInteger(receipt.bytes) || receipt.bytes < 1
      || !Number.isFinite(Date.parse(receipt.started_at))
      || !Number.isFinite(Date.parse(receipt.finished_at))
      || Date.parse(receipt.finished_at) < Date.parse(receipt.started_at)) fail(code);
  return true;
}

export function validatePhysicalMetadata(value, expected) {
  const code = 'PHYSICAL_METADATA';
  exactKeys(value, ['dev', 'gid', 'ino', 'mode', 'mtime_ns', 'nlink', 'size', 'symlink', 'type', 'uid'], code);
  if (value.uid !== expected.uid || value.gid !== expected.gid || (Number(value.mode) & 0o777) !== expected.mode) fail(code);
  if (value.type !== 'file' || value.symlink !== false || value.nlink !== 1 || !Number.isInteger(value.size) || value.size < 0) fail(code);
  for (const field of ['dev', 'ino', 'mtime_ns']) if (!/^[0-9]+$/.test(String(value[field]))) fail(code);
  return true;
}

const SIMULATOR_PHASES = Object.freeze([
  'SELECT_DEVICE', 'RESOLVE_CONTAINER', 'INSTALL_PROBE', 'LAUNCH_PROBE',
  'ACK_PROBE', 'REMOVE_PROBE', 'REOBSERVE',
]);

export function validateSimulatorGateReceipt(receipt) {
  const code = 'SIMULATOR_GATE';
  exactKeys(receipt, [
    'app_installation_sha256', 'attempts', 'authority_sha', 'bundle_id',
    'container_identity_sha256', 'controller_generation_id', 'device_selection_sha256',
    'phase_receipt_hashes', 'phases', 'probe_ack_sha256', 'probe_config_sha256',
    'probe_credential_sha256', 'purpose', 'raw_container_path_reported',
    'removal_proof_sha256', 'runtime_sha256', 'schema_version',
    'simulator_generation_id', 'source_commit', 'terminal_state',
  ], code);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_SIMULATOR_GATE_RECEIPT_V2' || receipt.bundle_id !== BUNDLE_ID || receipt.terminal_state !== 'SIMULATOR_GATE_PASS' || receipt.raw_container_path_reported !== false) fail(code);
  requireSha(receipt.authority_sha, code, [40]);
  requireSha(receipt.source_commit, code, [40]);
  validateGenerationId(receipt.controller_generation_id);
  validateGenerationId(receipt.simulator_generation_id);
  for (const field of ['app_installation_sha256', 'container_identity_sha256', 'device_selection_sha256', 'probe_ack_sha256', 'probe_config_sha256', 'probe_credential_sha256', 'removal_proof_sha256', 'runtime_sha256']) requireSha(receipt[field], code);
  if (JSON.stringify(receipt.phases) !== JSON.stringify(SIMULATOR_PHASES) || !Array.isArray(receipt.phase_receipt_hashes) || receipt.phase_receipt_hashes.length !== SIMULATOR_PHASES.length) fail(code);
  for (const value of receipt.phase_receipt_hashes) requireSha(value, code);
  exactKeys(receipt.attempts, ['ack', 'install', 'launch', 'remove', 'reobserve', 'resolve', 'select'], code);
  if (Object.values(receipt.attempts).some((value) => value !== 1)) fail(code);
  return true;
}

export function parseSshG(bytes) {
  const code = 'SSH_G_PARSE';
  const buffer = Buffer.from(bytes);
  if (buffer.length === 0 || buffer.includes(0)) fail(code);
  const text = buffer.toString('utf8');
  if (text.includes('\r') || !text.endsWith('\n')) fail(code);
  const records = [];
  for (const [ordinal, line] of text.slice(0, -1).split('\n').entries()) {
    const separator = line.indexOf(' ');
    if (separator < 1) fail(code);
    const rawKey = line.slice(0, separator);
    const value = line.slice(separator + 1);
    if (!/^[A-Za-z0-9]+$/.test(rawKey)) fail(code);
    const key = rawKey.toLowerCase();
    records.push({ key, value, ordinal });
  }
  if (records.length === 0) fail(code);
  return records;
}

export function validateSshTrustDescriptor(descriptor, records, expected = null) {
  const code = 'SSH_TRUST_DESCRIPTOR';
  exactKeys(descriptor, [
    'authority_sha', 'destination_sha256', 'host_key_ed25519_fingerprint_sha256',
    'identity_public_key_fingerprint_sha256', 'identity_public_key_sha256',
    'isolated_config_sha256', 'known_hosts_sha256', 'native_key_order',
    'native_record_count', 'native_records_sha256', 'purpose',
    'raw_destination_reported', 'remote_generation_id', 'schema_version',
    'ssh_code_signature_sha256', 'ssh_executable_path_sha256',
    'ssh_executable_sha256', 'ssh_version_sha256',
  ], code);
  if (descriptor.schema_version !== 1
      || descriptor.purpose !== 'CI3_MAC_SSH_TRUST_DESCRIPTOR_V1'
      || descriptor.raw_destination_reported !== false) fail(code);
  requireSha(descriptor.authority_sha, code, [40]);
  validateGenerationId(descriptor.remote_generation_id);
  for (const field of [
    'destination_sha256', 'host_key_ed25519_fingerprint_sha256',
    'identity_public_key_fingerprint_sha256', 'identity_public_key_sha256',
    'isolated_config_sha256', 'known_hosts_sha256', 'native_records_sha256',
    'ssh_code_signature_sha256', 'ssh_executable_path_sha256',
    'ssh_executable_sha256', 'ssh_version_sha256',
  ]) requireSha(descriptor[field], code);
  if (!Array.isArray(records) || descriptor.native_record_count !== records.length
      || descriptor.native_records_sha256 !== sha256(canonicalJson(records))
      || !Array.isArray(descriptor.native_key_order)
      || JSON.stringify(descriptor.native_key_order) !== JSON.stringify(records.map(({ key }) => key))) fail(code);
  if (expected) {
    const bindings = {
      authoritySha: 'authority_sha',
      remoteGenerationId: 'remote_generation_id',
      executablePathSha256: 'ssh_executable_path_sha256',
      executableSha256: 'ssh_executable_sha256',
      codeSignatureSha256: 'ssh_code_signature_sha256',
      versionSha256: 'ssh_version_sha256',
      configSha256: 'isolated_config_sha256',
      knownHostsSha256: 'known_hosts_sha256',
      identityPublicKeySha256: 'identity_public_key_sha256',
      identityPublicKeyFingerprintSha256: 'identity_public_key_fingerprint_sha256',
      hostKeyFingerprintSha256: 'host_key_ed25519_fingerprint_sha256',
      destinationSha256: 'destination_sha256',
    };
    for (const [expectedField, descriptorField] of Object.entries(bindings)) {
      if (expected[expectedField] !== undefined && descriptor[descriptorField] !== expected[expectedField]) fail(code);
    }
  }
  validateSshSecurityPolicy(records);
  return true;
}

export function buildSshProvenance({
  executableSha256, codeSignatureSha256, effectiveConfigSha256, configSha256,
  knownHostsSha256, identityPublicKeySha256, identityPublicKeyFingerprintSha256,
  hostKeyEd25519Sha256, destinationSha256, versionSha256, trustDescriptorSha256,
} = {}) {
  const code = 'SSH_PROVENANCE';
  const values = [
    executableSha256, codeSignatureSha256, effectiveConfigSha256, configSha256,
    knownHostsSha256, identityPublicKeySha256, identityPublicKeyFingerprintSha256,
    hostKeyEd25519Sha256, destinationSha256, versionSha256, trustDescriptorSha256,
  ];
  for (const value of values) requireSha(value, code);
  return {
    executable_sha256: executableSha256,
    code_signature_sha256: codeSignatureSha256,
    effective_config_sha256: effectiveConfigSha256,
    config_sha256: configSha256,
    known_hosts_sha256: knownHostsSha256,
    identity_public_key_sha256: identityPublicKeySha256,
    identity_public_key_fingerprint_sha256: identityPublicKeyFingerprintSha256,
    host_key_ed25519_sha256: hostKeyEd25519Sha256,
    destination_sha256: destinationSha256,
    version_sha256: versionSha256,
    trust_descriptor_sha256: trustDescriptorSha256,
  };
}

export function buildRemoteCatCommand(remotePath) {
  if (typeof remotePath !== 'string'
      || !/^\/[A-Za-z0-9._/-]+$/.test(remotePath)
      || remotePath.includes('//') || remotePath.includes('/../') || remotePath.endsWith('/')) fail('REMOTE_PATH');
  return `exec /usr/bin/cat -- ${remotePath}`;
}

export function deriveRemoteAuthorityBindings(operationRemote) {
  const code = 'REMOTE_AUTHORITY_BINDING';
  exactKeys(operationRemote, ['config_path', 'credential_path', 'receipt_path'], code);
  return Object.fromEntries(['receipt', 'config', 'credential'].map((kind) => {
    const remotePath = operationRemote[`${kind}_path`];
    const command = buildRemoteCatCommand(remotePath);
    return [kind, {
      path_sha256: sha256(Buffer.from(remotePath)),
      command_sha256: sha256(Buffer.from(command)),
    }];
  }));
}

export function buildSshReadArgv({ configPath, alias, remotePath } = {}) {
  if (!path.isAbsolute(configPath ?? '') || !/^ci3-[a-z0-9-]+$/.test(alias ?? '')) fail('SSH_AUTHORITY');
  return ['-F', configPath, alias, buildRemoteCatCommand(remotePath)];
}

const REMOTE_CONFIG_KEYS = Object.freeze([
  'bridge_authority_sha', 'cleanup_deadline', 'environment', 'mobile_bff_origin',
  'schema_version', 'staging_project_ref', 'supabase_anon_key', 'supabase_url',
]);
const REMOTE_CREDENTIAL_KEYS = Object.freeze([
  'cleanup_required', 'created_at', 'email', 'environment', 'expires_at',
  'password', 'project_ref', 'schema_version', 'synthetic_marker',
]);
const REMOTE_RECEIPT_KEYS = Object.freeze([
  'schema_version', 'purpose', 'created_at_utc', 'authority_commit', 'authority_parent',
  'authority_tree', 'authority_subject', 'generator_blob_sha', 'generator_file_sha256',
  'controller_blob_oid', 'controller_file_sha256', 'launcher_blob_oid',
  'launcher_file_sha256', 'launcher_target_environment', 'launcher_runtime_path',
  'zsh_syntax_validation_deferred', 'zsh_syntax_validation_required_environment',
  'zsh_syntax_validation_required_before_network', 'zsh_syntax_validation_status',
  'predecessor_launcher_structural_skeleton_sha256',
  'current_launcher_structural_skeleton_sha256', 'launcher_structural_skeleton_equal',
  'anchor_writer_blob_oid', 'anchor_writer_file_sha256',
  'authority_tree_manifest_sha256', 'remote_bundle_generation_id', 'source_generation_id',
  'source_env_descriptor_identity_sha256', 'env_source_sha256', 'env_receipt_sha256',
  'deployment_receipt_sha256', 'credential_source_path', 'credential_source_sha256',
  'provisioning_receipt_sha256', 'output_config_sha256', 'output_filenames',
  'staging_project_ref', 'implementation_sha', 'preview_deployment_count',
  'production_deployment_count', 'env_preview_count', 'env_production_count',
  'env_development_count', 'sso_state', 'cleanup_deadline', 'service_role_emitted',
  'token_emitted', 'raw_values_reported', 'primary_opened', 'remote_bundle_immutable',
  'terminal_scan_ids',
]);
const REMOTE_SOURCE_AUTHORITY = Object.freeze({
  credential_source_path: '/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json',
  env_source_sha256: '6aa784b9e5777a8924c4f37c1a9081cd040e399e30abfe5255978e1c1e571b9d',
  env_receipt_sha256: '44d0da30244f2340827698caa1aae85410b6a34d5c50a312a8b9e5e9bbe08978',
  deployment_receipt_sha256: 'f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6',
  credential_source_sha256: 'd36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208',
  provisioning_receipt_sha256: '5ed29995fa906d3774384d5a1aa9157516fa9f3e3dd0d320beff138b6aeedfcb',
  implementation_sha: 'e3e1e252b48e42554e75899b950692c05186f60d',
});

export function validateLauncherGateReceipt(receipt, code = 'REMOTE_BUNDLE_SEMANTICS') {
  if (!isPlainObject(receipt)
      || receipt.launcher_target_environment !== 'mac_local' || receipt.launcher_runtime_path !== '/bin/zsh'
      || receipt.zsh_syntax_validation_deferred !== true
      || receipt.zsh_syntax_validation_required_environment !== 'mac_local'
      || receipt.zsh_syntax_validation_required_before_network !== true
      || receipt.zsh_syntax_validation_status !== 'not_executed_on_vps'
      || receipt.launcher_structural_skeleton_equal !== true
      || !isSha(receipt.predecessor_launcher_structural_skeleton_sha256, [64])
      || receipt.current_launcher_structural_skeleton_sha256 !== receipt.predecessor_launcher_structural_skeleton_sha256) fail(code);
  return true;
}

export function validateRemoteBundleSemantics({ context, configBytes, credentialBytes, receiptBytes }) {
  const code = 'REMOTE_BUNDLE_SEMANTICS';
  let config;
  let credential;
  let receipt;
  try {
    config = JSON.parse(Buffer.from(configBytes).toString('utf8'));
    credential = JSON.parse(Buffer.from(credentialBytes).toString('utf8'));
    receipt = JSON.parse(Buffer.from(receiptBytes).toString('utf8'));
  } catch { fail(code); }
  if (!isPlainObject(config) || !isPlainObject(credential) || !isPlainObject(receipt)) fail(code);
  exactKeys(config, REMOTE_CONFIG_KEYS, code);
  exactKeys(credential, REMOTE_CREDENTIAL_KEYS, code);
  exactKeys(receipt, REMOTE_RECEIPT_KEYS, code);
  if (config.schema_version !== 1 || config.environment !== 'staging'
      || config.bridge_authority_sha !== context?.authority?.commit
      || typeof config.staging_project_ref !== 'string'
      || !config.staging_project_ref
      || typeof config.supabase_url !== 'string'
      || typeof config.mobile_bff_origin !== 'string'
      || typeof config.supabase_anon_key !== 'string'
      || !Number.isFinite(Date.parse(config.cleanup_deadline))) fail(code);
  let supabaseUrl;
  let bffUrl;
  try { supabaseUrl = new URL(config.supabase_url); bffUrl = new URL(config.mobile_bff_origin); } catch { fail(code); }
  if (supabaseUrl.protocol !== 'https:' || bffUrl.protocol !== 'https:'
      || !supabaseUrl.hostname.startsWith(`${config.staging_project_ref}.`)) fail(code);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING_WITH_CANONICAL_ENV_RECEIPT_V1'
      || receipt.authority_commit !== context.authority.commit
      || receipt.authority_parent !== context.authority.parent
      || receipt.authority_tree !== context.authority.tree
      || receipt.authority_subject !== context.authority.subject
      || receipt.authority_tree_manifest_sha256 !== context.authority.manifest_sha256
      || receipt.remote_bundle_generation_id !== context.generations.remote
      || !/^src-[a-f0-9]{64}$/.test(receipt.source_generation_id ?? '')
      || receipt.output_config_sha256 !== sha256(configBytes)
      || context.remote.receipt_sha256 !== sha256(receiptBytes)
      || context.remote.config_sha256 !== sha256(configBytes)
      || context.remote.credential_sha256 !== sha256(credentialBytes)
      || receipt.credential_source_sha256 !== sha256(credentialBytes)
      || receipt.raw_values_reported !== false
      || JSON.stringify(receipt.terminal_scan_ids) !== JSON.stringify(TERMINAL_SCAN_IDS)) fail(code);
  validateLauncherGateReceipt(receipt, code);
  const componentFields = {
    generator: ['generator_blob_sha', 'generator_file_sha256'],
    controller: ['controller_blob_oid', 'controller_file_sha256'],
    launcher: ['launcher_blob_oid', 'launcher_file_sha256'],
    writer: ['anchor_writer_blob_oid', 'anchor_writer_file_sha256'],
  };
  for (const [name, [oidField, hashField]] of Object.entries(componentFields)) {
    if (receipt[oidField] !== context.authority.components[name].blob_oid
        || receipt[hashField] !== context.authority.components[name].sha256) fail(code);
  }
  if (credential.schema_version !== 1 || credential.environment !== 'staging'
      || credential.cleanup_required !== true || credential.synthetic_marker !== 'ci3-synthetic-patient'
      || credential.project_ref !== config.staging_project_ref
      || !Number.isFinite(Date.parse(credential.created_at))
      || !Number.isFinite(Date.parse(credential.expires_at))
      || Date.parse(credential.expires_at) <= Date.parse(credential.created_at)
      || credential.expires_at !== config.cleanup_deadline
      || receipt.cleanup_deadline !== config.cleanup_deadline
      || receipt.staging_project_ref !== config.staging_project_ref
      || typeof credential.email !== 'string' || !credential.email.includes('@')
      || typeof credential.password !== 'string' || credential.password.length === 0) fail(code);
  for (const [field, expected] of Object.entries(REMOTE_SOURCE_AUTHORITY)) {
    if (receipt[field] !== expected) fail(code);
  }
  if (receipt.created_at_utc !== context.authority.committed_at_utc
      || !Number.isFinite(Date.parse(receipt.created_at_utc))
      || JSON.stringify(receipt.output_filenames) !== JSON.stringify(['mobile-staging-config.json', 'bridge.receipt.json'])
      || receipt.preview_deployment_count !== 1 || receipt.production_deployment_count !== 0
      || receipt.env_preview_count !== 3 || receipt.env_production_count !== 0
      || receipt.env_development_count !== 0 || receipt.sso_state !== null
      || receipt.service_role_emitted !== false || receipt.token_emitted !== false
      || receipt.primary_opened !== false || receipt.remote_bundle_immutable !== true) fail(code);
  for (const field of ['source_env_descriptor_identity_sha256']) requireSha(receipt[field], code);
  return { config, credential, receipt };
}

const FORBIDDEN_SSH_VALUES = Object.freeze({
  forwardagent: new Set(['yes']),
  passwordauthentication: new Set(['yes']),
  kbdinteractiveauthentication: new Set(['yes']),
  proxycommand: null,
  proxyjump: null,
  controlmaster: new Set(['auto', 'yes', 'ask', 'autoask']),
  localcommand: null,
  permitlocalcommand: new Set(['yes']),
  clearallforwardings: new Set(['no']),
  stricthostkeychecking: new Set(['no', 'ask', 'accept-new']),
  requesttty: new Set(['yes', 'force', 'auto']),
  gatewayports: new Set(['yes', 'clientspecified']),
  exitonforwardfailure: new Set(['no']),
  hostbasedauthentication: new Set(['yes']),
  gssapiauthentication: new Set(['yes']),
  forwardx11: new Set(['yes']),
  forwardx11trusted: new Set(['yes']),
  tunnel: new Set(['yes', 'point-to-point', 'ethernet']),
  localforward: null,
  remoteforward: null,
  dynamicforward: null,
  sendenv: null,
  setenv: null,
  addkeystoagent: new Set(['yes', 'ask', 'confirm']),
  forkafterauthentication: new Set(['yes']),
  identityagent: null,
});

// Frozen from the complete native macOS OpenSSH `ssh -G` surface exercised by
// this authority. Unknown future keys fail closed until a new authority review.
const SSH_G_ALLOWED_KEYS = new Set([
  'host', 'user', 'hostname', 'port', 'addressfamily', 'batchmode',
  'canonicalizefallbacklocal', 'canonicalizehostname', 'checkhostip',
  'compression', 'controlmaster', 'enablesshkeysign', 'clearallforwardings',
  'exitonforwardfailure', 'fingerprinthash', 'forwardx11', 'forwardx11trusted',
  'gatewayports', 'gssapiauthentication', 'gssapidelegatecredentials',
  'hashknownhosts', 'hostbasedauthentication', 'identitiesonly',
  'kbdinteractiveauthentication', 'nohostauthenticationforlocalhost',
  'nohostauthenticationforproxycommand', 'passwordauthentication',
  'permitlocalcommand', 'proxyusefdpass', 'pubkeyauthentication', 'requesttty',
  'sessiontype', 'stdinnull', 'forkafterauthentication',
  'streamlocalbindunlink', 'stricthostkeychecking', 'tcpkeepalive', 'tunnel',
  'verifyhostkeydns', 'visualhostkey', 'updatehostkeys',
  'enableescapecommandline', 'warnweakcrypto', 'applemultipath',
  'gssapikexalgorithms', 'gssapikeyexchange', 'gssapirenewalforcesrekey', 'gssapitrustdns',
  'canonicalizemaxdots', 'connectionattempts', 'forwardx11timeout',
  'numberofpasswordprompts', 'serveralivecountmax', 'serveraliveinterval',
  'requiredrsasize', 'obscurekeystroketiming', 'ciphers', 'hostkeyalgorithms',
  'hostbasedacceptedalgorithms', 'kexalgorithms', 'casignaturealgorithms',
  'loglevel', 'macs', 'securitykeyprovider', 'pubkeyacceptedalgorithms',
  'xauthlocation', 'identityfile', 'canonicaldomains', 'globalknownhostsfile',
  'userknownhostsfile', 'logverbose', 'channeltimeout', 'permitremoteopen',
  'addkeystoagent', 'forwardagent', 'connecttimeout', 'tunneldevice',
  'canonicalizepermittedcnames', 'controlpersist', 'escapechar', 'ipqos',
  'rekeylimit', 'streamlocalbindmask', 'syslogfacility',
  'sendenv', 'setenv', 'identityagent', 'localforward', 'remoteforward', 'dynamicforward',
]);

export function validateSshSecurityPolicy(records) {
  const code = 'SSH_POLICY';
  if (!Array.isArray(records) || records.length === 0) fail(code);
  const addKeysToAgent = records.filter(({ key }) => key === 'addkeystoagent');
  if (addKeysToAgent.length > 0
      && (addKeysToAgent.length !== 1
        || !['no', 'false'].includes(addKeysToAgent[0].value))) fail(code);
  for (const { key, value } of records) {
    if (!SSH_G_ALLOWED_KEYS.has(key) || typeof value !== 'string') fail(code);
    if (!Object.hasOwn(FORBIDDEN_SSH_VALUES, key)) continue;
    const forbidden = FORBIDDEN_SSH_VALUES[key];
    if (forbidden === null) {
      if (!['none', ''].includes(value)) fail(code);
    } else if (forbidden.has(value.toLowerCase())) fail(code);
  }
  return true;
}

export async function runSshG({ alias, configPath }) {
  if (!/^ci3-[a-z0-9-]+$/.test(alias ?? '') || !path.isAbsolute(configPath ?? '')) fail('SSH_G_INPUT');
  const result = spawnSync(SSH_PATH, ['-G', '-F', configPath, alias], {
    encoding: null,
    env: CLOSED_BOOTSTRAP_ENVIRONMENT,
    maxBuffer: 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.status !== 0 || result.signal || result.stderr.length !== 0) fail('SSH_G_EXECUTION');
  const records = parseSshG(result.stdout);
  validateSshSecurityPolicy(records);
  return { exit: 0, records, sha256: sha256(result.stdout), network_calls: 0 };
}

export function validateScanIds(ids) {
  if (JSON.stringify(ids) !== JSON.stringify(TERMINAL_SCAN_IDS)) fail('TERMINAL_SCAN_SET');
  return true;
}

const SCAN_CLASS_PATTERNS = Object.freeze({
  argv: Object.freeze({ secret: /(?:password|service[_-]?role)=\S+/gi, pii: /--(?:email|phone)=\S+/gi, jwt: /\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g, token: /(?:token|authorization)=\S+/gi, raw_destination: /(?:host|destination)=\S+/gi }),
  history: Object.freeze({ secret: /(?:export\s+)?(?:PASSWORD|SERVICE_ROLE)=\S+/g, pii: /\b[^\s@]+@[^\s@]+\.[^\s@]+\b/g, jwt: /\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g, token: /(?:Bearer\s+|TOKEN=)\S+/gi, raw_destination: /(?:ssh\s+\S+@|\b(?:\d{1,3}\.){3}\d{1,3}\b)/g }),
  'terminal-log': Object.freeze({ secret: /(?:password|secret|service[_-]?role)[\s:=]+\S+/gi, pii: /\b[^\s@]+@[^\s@]+\.[^\s@]+\b/g, jwt: /\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g, token: /(?:Bearer\s+|token[\s:=]+)\S+/gi, raw_destination: /(?:host|destination)[\s:=]+\S+|\b(?:\d{1,3}\.){3}\d{1,3}\b/gi }),
  attachment: Object.freeze({ secret: /"(?:password|secret|service_role)"\s*:\s*"[^"]+"/gi, pii: /"(?:email|phone)"\s*:\s*"[^"]+"/gi, jwt: /"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"/g, token: /"(?:token|authorization)"\s*:\s*"[^"]+"/gi, raw_destination: /"(?:host|destination|origin)"\s*:\s*"[^"]+"/gi }),
  xcresult: Object.freeze({ secret: /(?:password|secret|serviceRole)\s*=\s*\S+/gi, pii: /(?:email|phone)\s*=\s*\S+/gi, jwt: /\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g, token: /(?:token|authorization)\s*=\s*\S+/gi, raw_destination: /(?:host|destination|origin)\s*=\s*\S+/gi }),
  runtime: Object.freeze({ secret: /(?:PASSWORD|SECRET|SERVICE_ROLE)=\S+/g, pii: /(?:EMAIL|PHONE)=\S+/g, jwt: /\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g, token: /(?:TOKEN|AUTHORIZATION)=\S+/g, raw_destination: /(?:HOST|DESTINATION|ORIGIN)=\S+|\b(?:\d{1,3}\.){3}\d{1,3}\b/g }),
});

const GENERIC_SCAN_PATTERNS = Object.freeze({
  secret: /(?:password|secret|service[_-]?role)[\s:=]+\S+/gi,
  pii: /\b[^\s@]+@[^\s@]+\.[^\s@]+\b|\b(?:\d{1,3}\.){3}\d{1,3}\b/g,
  jwt: /\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g,
  token: /(?:Bearer\s+|token|authorization)[\s:=]+\S+/gi,
  raw_destination: /(?:host|destination|origin)[\s:=]+\S+|\b(?:\d{1,3}\.){3}\d{1,3}\b/gi,
});

export function scanTerminalSurface(scanId, bytes) {
  const patterns = SCAN_CLASS_PATTERNS[scanId];
  if (!patterns) fail('TERMINAL_SCAN_SET');
  const text = Buffer.from(bytes).toString('utf8');
  const counters = {};
  for (const key of ['secret', 'pii', 'jwt', 'token', 'raw_destination']) {
    const ranges = [];
    for (const expression of [patterns[key], GENERIC_SCAN_PATTERNS[key]]) {
      const matcher = new RegExp(expression.source, expression.flags);
      for (const match of text.matchAll(matcher)) {
        const start = match.index;
        ranges.push([start, start + match[0].length]);
      }
    }
    ranges.sort(([leftStart, leftEnd], [rightStart, rightEnd]) => leftStart - rightStart || leftEnd - rightEnd);
    const disjoint = [];
    for (const [start, end] of ranges) {
      const previous = disjoint.at(-1);
      if (previous && start < previous[1]) previous[1] = Math.max(previous[1], end);
      else disjoint.push([start, end]);
    }
    counters[key] = disjoint.length;
  }
  return { scan_id: scanId, counters, total: Object.values(counters).reduce((sum, count) => sum + count, 0) };
}

export function frameScannedTerminalPayloads(scanId, payloads) {
  const code = 'TERMINAL_SCAN_SOURCE';
  if (!['history', 'terminal-log', 'attachment'].includes(scanId)
      || !Array.isArray(payloads)
      || !payloads.every((value) => Buffer.isBuffer(value) || value instanceof Uint8Array)) fail(code);
  const records = payloads.map((value, index) => {
    const bytes = Buffer.from(value);
    if (scanTerminalSurface(scanId, bytes).total !== 0) fail('TERMINAL_SCAN_MATCH');
    return {
      sequence: index,
      content_sha256: sha256(bytes),
      content_byte_length: bytes.length,
      content_base64: bytes.toString('base64'),
    };
  });
  return canonicalJson(records);
}

const RUNTIME_ENV_ALLOWLIST = Object.freeze(['HOME', 'LANG', 'LC_ALL', 'PATH', 'TMPDIR']);
const CREDENTIAL_LIKE_ENV = /(?:SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|AUTHORIZATION|COOKIE|SESSION|PRIVATE|ACCESS_KEY|SERVICE_ROLE|NODE_OPTIONS|SSH_AUTH_SOCK)/i;

export function sanitizeTerminalRuntimeEnvironment(environment) {
  const code = 'RUNTIME_ENVIRONMENT';
  if (!isPlainObject(environment)) fail(code);
  for (const [name, value] of Object.entries(environment)) {
    if (typeof value !== 'string' || CREDENTIAL_LIKE_ENV.test(name)) fail(code);
  }
  const sanitized = {};
  for (const name of RUNTIME_ENV_ALLOWLIST) {
    if (Object.hasOwn(environment, name)) sanitized[name] = environment[name];
  }
  return Object.fromEntries(Object.entries(sanitized).sort(([left], [right]) => left.localeCompare(right)));
}

const CLOSED_BOOTSTRAP_ENVIRONMENT = Object.freeze({
  HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin',
});

export function validateClosedBootstrapEnvironment(environment) {
  const code = 'BOOTSTRAP_ENVIRONMENT';
  if (!isPlainObject(environment)
      || !canonicalJson(environment).equals(canonicalJson(CLOSED_BOOTSTRAP_ENVIRONMENT))) fail(code);
  return true;
}

export async function validateStableSshSnapshots({ before, afterSshG, afterConnect } = {}) {
  const code = 'SSH_SNAPSHOT_DRIFT';
  if (!isPlainObject(before) || !isPlainObject(afterSshG) || !isPlainObject(afterConnect)) fail(code);
  const roles = ['config', 'identity', 'known_hosts', 'public_key', 'trust_descriptor'];
  exactKeys(before, roles, code);
  for (const snapshot of [before, afterSshG, afterConnect]) {
    exactKeys(snapshot, roles, code);
    for (const role of roles) {
      exactKeys(snapshot[role], ['identity_sha256', 'path', 'sha256'], code);
      if (!path.isAbsolute(snapshot[role].path)) fail(code);
      requireSha(snapshot[role].sha256, code);
      requireSha(snapshot[role].identity_sha256, code);
    }
    if (!canonicalJson(snapshot).equals(canonicalJson(before))) fail(code);
  }
  return true;
}

function canonicalIntegerDecimal(value, code = 'PHYSICAL_IDENTITY') {
  if (typeof value === 'bigint') return value.toString();
  if (typeof value === 'number' && Number.isSafeInteger(value)) return String(value);
  if (typeof value === 'string' && /^-?(?:0|[1-9]\d*)$/.test(value)) return value;
  fail(code);
}

function physicalIdentitySha256({ uid, gid, mode, nlink, size, mtime_ns: mtimeNs, dev, ino }) {
  const fields = {
    uid: canonicalIntegerDecimal(uid),
    gid: canonicalIntegerDecimal(gid),
    mode: (BigInt(canonicalIntegerDecimal(mode)) & 0o777n).toString(),
    nlink: canonicalIntegerDecimal(nlink),
    size: canonicalIntegerDecimal(size),
    mtime: canonicalIntegerDecimal(mtimeNs),
    dev: canonicalIntegerDecimal(dev),
    ino: canonicalIntegerDecimal(ino),
  };
  return sha256(Buffer.from([
    `uid=${fields.uid}`, `gid=${fields.gid}`, `mode=${fields.mode}`,
    `nlink=${fields.nlink}`, `size=${fields.size}`, `mtime=${fields.mtime}`,
    `dev=${fields.dev}`, `ino=${fields.ino}`,
  ].join(';')));
}

export function physicalIdentityFromBigIntStat(observed) {
  const required = ['uid', 'gid', 'mode', 'nlink', 'size', 'mtimeNs', 'dev', 'ino'];
  if (!isPlainObject(observed) || required.some((field) => typeof observed[field] !== 'bigint')) {
    fail('PHYSICAL_IDENTITY');
  }
  return {
    identity_sha256: physicalIdentitySha256({
      uid: observed.uid, gid: observed.gid, mode: observed.mode,
      nlink: observed.nlink, size: observed.size, mtime_ns: observed.mtimeNs,
      dev: observed.dev, ino: observed.ino,
    }),
  };
}

export async function observeSimulatorContainerIdentity(resolved, { lstatFn = lstat } = {}) {
  const code = 'SIMULATOR_GATE';
  if (!path.isAbsolute(resolved ?? '') || typeof lstatFn !== 'function') fail(code);
  const observed = await lstatFn(resolved, { bigint: true }).catch(() => fail(code));
  const fields = ['uid', 'gid', 'mode', 'nlink', 'size', 'mtimeNs', 'dev', 'ino'];
  if (!observed?.isDirectory?.() || observed.isSymbolicLink?.()
      || fields.some((field) => typeof observed[field] !== 'bigint')) fail(code);
  return physicalIdentityFromBigIntStat(observed);
}

function safeStatNumber(value, code) {
  if (typeof value !== 'bigint' || value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER)) fail(code);
  return Number(value);
}

function metadataFromBigIntStat(observed, code = 'PHYSICAL_IDENTITY') {
  const identity = physicalIdentityFromBigIntStat(observed);
  return {
    ...identity,
    metadata: {
      dev: observed.dev.toString(), gid: safeStatNumber(observed.gid, code), ino: observed.ino.toString(),
      mode: safeStatNumber(observed.mode & 0o777n, code), mtime_ns: observed.mtimeNs.toString(),
      nlink: safeStatNumber(observed.nlink, code), size: safeStatNumber(observed.size, code),
      uid: safeStatNumber(observed.uid, code),
    },
  };
}

function descriptorIdentity(observed) {
  return metadataFromBigIntStat(observed).metadata;
}

function sameBigIntStat(left, right) {
  return ['dev', 'ino', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtimeNs']
    .every((field) => left[field] === right[field]);
}

async function revalidateRetainedDirectoryChain(retained, code, { allowParentMutation = false } = {}) {
  for (let index = 0; index < retained.length; index += 1) {
    const entry = retained[index];
    const fromDescriptor = descriptorIdentity(await entry.handle.stat({ bigint: true }));
    const fromPath = descriptorIdentity(await lstat(entry.path, { bigint: true }).catch(() => fail(code)));
    if (!canonicalJson(fromDescriptor).equals(canonicalJson(fromPath))) fail(code);
    if (allowParentMutation && index === retained.length - 1) {
      for (const field of ['dev', 'ino', 'uid', 'gid', 'mode']) {
        if (fromDescriptor[field] !== entry.identity[field]) fail(code);
      }
    } else if (!canonicalJson(fromDescriptor).equals(canonicalJson(entry.identity))) fail(code);
  }
}

export async function descriptorRelativeFileTransaction({
  root, relativePath, operation, bytes = null, expectedMode,
  expectedUid, expectedGid, allowedDirectoryModes, scheduler = null,
  helperPath = null, helperSha256 = null,
  requireImmutable = false, makeImmutable = false,
} = {}) {
  if (!path.isAbsolute(root ?? '') || typeof relativePath !== 'string'
      || path.isAbsolute(relativePath) || relativePath.includes('..')
      || !['read', 'create-exclusive'].includes(operation)
      || !Number.isInteger(expectedMode) || !Number.isInteger(expectedUid) || !Number.isInteger(expectedGid)
      || !Array.isArray(allowedDirectoryModes) || allowedDirectoryModes.length === 0
      || typeof requireImmutable !== 'boolean' || typeof makeImmutable !== 'boolean'
      || (makeImmutable && operation !== 'create-exclusive')
      || (operation === 'create-exclusive' && !Buffer.isBuffer(bytes))) fail('DESCRIPTOR_ARGUMENT');
  const parts = relativePath.split('/');
  if (parts.some((part) => part.length === 0 || part === '.' || part === '..')) fail('DESCRIPTOR_ARGUMENT');
  if (helperPath !== null) {
    if (!path.isAbsolute(helperPath) || helperPath.includes('/../')) fail('DESCRIPTOR_HELPER');
    requireSha(helperSha256, 'DESCRIPTOR_HELPER');
    const helperBytes = await readFile(helperPath).catch(() => fail('DESCRIPTOR_HELPER'));
    if (sha256(helperBytes) !== helperSha256) fail('DESCRIPTOR_HELPER');
  } else if (process.platform !== 'linux') fail('DESCRIPTOR_HELPER');
  const retained = [];
  try {
    for (let index = 0; index < parts.length; index += 1) {
      const directoryPath = index === 0 ? root : path.join(root, ...parts.slice(0, index));
      const openPath = index > 0 && process.platform === 'linux'
        ? `/proc/self/fd/${retained.at(-1).handle.fd}/${parts[index - 1]}`
        : directoryPath;
      const handle = await open(
        openPath,
        FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_DIRECTORY | FS_CONSTANTS.O_NOFOLLOW,
      ).catch(() => fail('DESCRIPTOR_CHAIN'));
      const observed = await handle.stat({ bigint: true });
      const mode = safeStatNumber(observed.mode & 0o777n, 'DESCRIPTOR_CHAIN');
      if (!observed.isDirectory() || observed.uid !== BigInt(expectedUid) || observed.gid !== BigInt(expectedGid)
          || !allowedDirectoryModes.includes(mode) || (mode & 0o022) !== 0) {
        await handle.close();
        fail('DESCRIPTOR_CHAIN');
      }
      retained.push({ path: directoryPath, handle, identity: descriptorIdentity(observed) });
    }
    await scheduler?.afterChainOpen?.({ chain: retained.map(({ path: value, identity }) => ({ path: value, identity })) });
    await revalidateRetainedDirectoryChain(retained, 'DESCRIPTOR_CHAIN_DRIFT');
    const request = {
      schema_version: 1, purpose: 'CI3_DESCRIPTOR_RELATIVE_TRANSACTION_V1',
      root, relative_path: relativePath, operation, expected_mode: expectedMode, expected_uid: expectedUid,
      expected_gid: expectedGid, allowed_directory_modes: allowedDirectoryModes,
      bytes_base64: operation === 'create-exclusive' ? bytes.toString('base64') : '',
      require_immutable: requireImmutable, make_immutable: makeImmutable,
    };
    let parsed;
    if (helperPath !== null) {
      const result = spawnSync(helperPath, ['--descriptor-transaction'], {
        input: canonicalJson(request), encoding: 'utf8',
        env: CLOSED_BOOTSTRAP_ENVIRONMENT, stdio: ['pipe', 'pipe', 'pipe'], timeout: 30000,
      });
      if (result.status !== 0 || result.signal !== null) {
        if (result.stderr === 'ERROR DESCRIPTOR_NO_CLOBBER\n') fail('DESCRIPTOR_NO_CLOBBER');
        if (result.stderr === 'ERROR DESCRIPTOR_CHAIN\n') fail('DESCRIPTOR_CHAIN');
        fail('DESCRIPTOR_TRANSACTION');
      }
      if (result.stderr !== '') fail('DESCRIPTOR_TRANSACTION');
      try { parsed = JSON.parse(result.stdout); } catch { fail('DESCRIPTOR_TRANSACTION'); }
    } else {
      const parent = retained.at(-1).handle;
      const leafPath = `/proc/self/fd/${parent.fd}/${parts.at(-1)}`;
      const flags = operation === 'read'
        ? FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW
        : FS_CONSTANTS.O_RDWR | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW;
      const leaf = await open(leafPath, flags, expectedMode).catch((error) => {
        if (error?.code === 'EEXIST') fail('DESCRIPTOR_NO_CLOBBER');
        fail('DESCRIPTOR_TRANSACTION');
      });
      try {
        if (operation === 'create-exclusive') {
          await leaf.writeFile(bytes);
          await leaf.sync();
          await chmod(leafPath, expectedMode);
          if (makeImmutable) runFixedCommand('/usr/bin/chattr', ['+i', '--', leafPath]);
          await parent.sync();
        }
        const before = await leaf.stat({ bigint: true });
        if (!before.isFile() || before.uid !== BigInt(expectedUid) || before.gid !== BigInt(expectedGid)
            || before.nlink !== 1n || (before.mode & 0o777n) !== BigInt(expectedMode)) fail('DESCRIPTOR_TRANSACTION');
        const content = Buffer.alloc(safeStatNumber(before.size, 'DESCRIPTOR_TRANSACTION'));
        let offset = 0;
        while (offset < content.length) {
          const { bytesRead } = await leaf.read(content, offset, content.length - offset, offset);
          if (bytesRead < 1) fail('DESCRIPTOR_TRANSACTION');
          offset += bytesRead;
        }
        const after = await leaf.stat({ bigint: true });
        const relative = await lstat(leafPath, { bigint: true });
        let immutable = false;
        if (requireImmutable || makeImmutable) {
          const immutableOutput = runFixedCommand('/usr/bin/lsattr', ['-d', '--', path.join(retained.at(-1).path, parts.at(-1))]);
          immutable = /^\S*i\S*\s/.test(immutableOutput.stdout.toString('utf8'));
        }
        if (requireImmutable && !immutable) fail('DESCRIPTOR_TRANSACTION');
        if (!canonicalJson(descriptorIdentity(before)).equals(canonicalJson(descriptorIdentity(after)))
            || !canonicalJson(descriptorIdentity(after)).equals(canonicalJson(descriptorIdentity(relative)))) {
          fail('DESCRIPTOR_TRANSACTION');
        }
        parsed = { bytes_base64: content.toString('base64'), metadata: descriptorIdentity(after), immutable };
      } finally { await leaf.close(); }
    }
    await revalidateRetainedDirectoryChain(retained, 'DESCRIPTOR_CHAIN_DRIFT', {
      allowParentMutation: operation === 'create-exclusive',
    });
    if (!isPlainObject(parsed.metadata) || typeof parsed.bytes_base64 !== 'string'
        || typeof parsed.immutable !== 'boolean') fail('DESCRIPTOR_TRANSACTION');
    const directoryChain = [];
    for (const entry of retained) {
      const observed = await entry.handle.stat({ bigint: true });
      const observedMetadata = metadataFromBigIntStat(observed, 'DESCRIPTOR_TRANSACTION');
      let immutable = false;
      if (process.platform === 'linux' && (requireImmutable || makeImmutable)) {
        const attributes = runFixedCommand('/usr/bin/lsattr', ['-d', '--', entry.path]);
        immutable = /^\S*i\S*\s/.test(attributes.stdout.toString('utf8'));
      }
      directoryChain.push({
        path: entry.path, uid: observedMetadata.metadata.uid, gid: observedMetadata.metadata.gid,
        mode: observedMetadata.metadata.mode, nlink: observedMetadata.metadata.nlink,
        type: observed.isDirectory() ? 'directory' : 'other',
        symlink: false, immutable, identity_sha256: observedMetadata.identity_sha256,
      });
    }
    return {
      bytes: Buffer.from(parsed.bytes_base64, 'base64'), metadata: parsed.metadata,
      immutable: parsed.immutable, directoryChain,
    };
  } finally {
    for (const { handle } of retained.reverse()) await handle.close().catch(() => undefined);
  }
}

const PRIVILEGED_TERMINAL_PATH_KEYS = Object.freeze([
  'completeEvent', 'completeFinalScan', 'completeResult', 'journalFrame',
  'invokeWriterClaim', 'invokeWriterReceipt', 'invokeWriterResult',
  'marker', 'preAnchor', 'privilegedAuthority', 'settlement', 'stderrFrame', 'stdoutFrame',
  'terminalFinalScan', 'verifyAnchorClaim', 'verifyAnchorReceipt', 'verifyAnchorResult',
  'writerOutput',
]);

const PRIVILEGED_TERMINAL_ROOT_ENTRIES = Object.freeze([
  'complete-final-scan.json', 'complete-result.json', 'controller-complete.event.json',
  'controller-journal.final.frame', 'controller-stderr.final.frame', 'controller-stdout.final.frame',
  'pre-anchor.json', 'privileged-authority.receipt.json', 'terminal-final-scan.json',
  'terminal-pass.marker.json', 'terminal-phases', 'terminal-settlement.json', 'writer',
  'writer-output.json',
]);

const PRIVILEGED_TERMINAL_PHASE_ENTRIES = Object.freeze([
  'invoke-writer.claim.json', 'invoke-writer.receipt.json', 'invoke-writer.result.json',
  'verify-anchor.claim.json', 'verify-anchor.receipt.json', 'verify-anchor.result.json',
]);

const PRIVILEGED_TERMINAL_WRITER_ENTRIES = Object.freeze(['ci3-terminal-anchor-writer']);

function validateTerminalPassContext(context, code = 'TERMINAL_TAIL_AUTHORITY') {
  if (!isPlainObject(context) || !isPlainObject(context.authority)
      || !isPlainObject(context.authority.components) || !isPlainObject(context.generations)) fail(code);
  requireSha(context.authority.commit, code, [40]);
  for (const [name, prefix] of Object.entries({
    remote: 'remote', controller: 'controller', simulator: 'simulator', terminal: 'terminal',
  })) if (!new RegExp(`^${prefix}-[a-f0-9]{64}$`).test(context.generations[name] ?? '')) fail(code);
  for (const name of ['controller', 'launcher']) requireSha(context.authority.components[name]?.sha256, code);
}

export function derivePrivilegedTerminalPassPaths({ context, journalGenerationRoot } = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  validateTerminalPassContext(context, code);
  if (!path.isAbsolute(journalGenerationRoot ?? '') || journalGenerationRoot.includes('/../')
      || path.basename(journalGenerationRoot) !== context.generations.controller
      || path.basename(path.dirname(journalGenerationRoot)) !== context.authority.commit) fail(code);
  const terminalRoot = path.join(
    '/Library/Application Support/Agentempp/ci3-terminal-authority',
    context.authority.commit, context.generations.terminal,
  );
  const phaseRoot = path.join(terminalRoot, 'terminal-phases');
  return Object.freeze({
    completeEvent: path.join(terminalRoot, 'controller-complete.event.json'),
    completeFinalScan: path.join(terminalRoot, 'complete-final-scan.json'),
    completeResult: path.join(terminalRoot, 'complete-result.json'),
    journalFrame: path.join(terminalRoot, 'controller-journal.final.frame'),
    invokeWriterClaim: path.join(phaseRoot, 'invoke-writer.claim.json'),
    invokeWriterReceipt: path.join(phaseRoot, 'invoke-writer.receipt.json'),
    invokeWriterResult: path.join(phaseRoot, 'invoke-writer.result.json'),
    marker: path.join(terminalRoot, 'terminal-pass.marker.json'),
    preAnchor: path.join(terminalRoot, 'pre-anchor.json'),
    privilegedAuthority: path.join(terminalRoot, 'privileged-authority.receipt.json'),
    settlement: path.join(terminalRoot, 'terminal-settlement.json'),
    stderrFrame: path.join(terminalRoot, 'controller-stderr.final.frame'),
    stdoutFrame: path.join(terminalRoot, 'controller-stdout.final.frame'),
    terminalFinalScan: path.join(terminalRoot, 'terminal-final-scan.json'),
    verifyAnchorClaim: path.join(phaseRoot, 'verify-anchor.claim.json'),
    verifyAnchorReceipt: path.join(phaseRoot, 'verify-anchor.receipt.json'),
    verifyAnchorResult: path.join(phaseRoot, 'verify-anchor.result.json'),
    writerOutput: path.join(terminalRoot, 'writer-output.json'),
  });
}

export function validatePrivilegedTerminalRootDirectoryEntries({
  terminalEntries, phaseEntries, writerEntries,
} = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  if (!Array.isArray(terminalEntries) || !Array.isArray(phaseEntries) || !Array.isArray(writerEntries)) fail(code);
  const normalizedTerminal = [...terminalEntries].sort();
  const normalizedPhases = [...phaseEntries].sort();
  const normalizedWriter = [...writerEntries].sort();
  if (new Set(normalizedTerminal).size !== normalizedTerminal.length
      || new Set(normalizedPhases).size !== normalizedPhases.length
      || new Set(normalizedWriter).size !== normalizedWriter.length
      || !canonicalJson(normalizedTerminal).equals(canonicalJson([...PRIVILEGED_TERMINAL_ROOT_ENTRIES].sort()))
      || !canonicalJson(normalizedPhases).equals(canonicalJson([...PRIVILEGED_TERMINAL_PHASE_ENTRIES].sort()))
      || !canonicalJson(normalizedWriter).equals(canonicalJson([...PRIVILEGED_TERMINAL_WRITER_ENTRIES].sort()))) fail(code);
  return true;
}

function exactTerminalPassPaths(paths, context) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  exactKeys(paths, PRIVILEGED_TERMINAL_PATH_KEYS, code);
  const markerRoot = path.dirname(paths.marker ?? '');
  const expectedTerminalRoot = path.join(
    '/Library/Application Support/Agentempp/ci3-terminal-authority',
    context.authority.commit, context.generations.terminal,
  );
  if (markerRoot !== expectedTerminalRoot) fail(code);
  const journalGenerationRoot = path.join(
    '/fixed.invalid/controller-journal', context.authority.commit, context.generations.controller,
  );
  const expected = derivePrivilegedTerminalPassPaths({ context, journalGenerationRoot });
  if (!canonicalJson(paths).equals(canonicalJson(expected))) fail(code);
  return expected;
}

function terminalPassPathHashes(paths) {
  return Object.fromEntries(PRIVILEGED_TERMINAL_PATH_KEYS.map((key) => [
    `${key.replace(/[A-Z]/g, (match) => `_${match.toLowerCase()}`)}_sha256`, sha256(Buffer.from(paths[key])),
  ]));
}

function validateTerminalPassInputs(inputs, code) {
  const keys = [
    'authorityReceiptBytes', 'completeBytes', 'completeEventBytes', 'completeFinalScanBytes',
    'invokeWriterClaimBytes', 'invokeWriterReceiptBytes', 'invokeWriterResultBytes',
    'journalFrameBytes', 'preAnchorBytes', 'settlementBytes', 'stderrBytes', 'stdoutBytes',
    'terminalFinalScanBytes', 'verifyAnchorClaimBytes', 'verifyAnchorReceiptBytes',
    'verifyAnchorResultBytes', 'writerOutputBytes',
  ];
  for (const key of keys) if (!Buffer.isBuffer(inputs[key])) fail(code);
  for (const key of ['journalFrameBytes', 'completeEventBytes', 'stdoutBytes', 'stderrBytes']) {
    if (scanTerminalSurface('terminal-log', inputs[key]).total !== 0) fail(code);
  }
  return keys;
}

function terminalPhaseObjectRoots(inputs) {
  return [
    ['invoke-writer-claim', inputs.invokeWriterClaimBytes],
    ['invoke-writer-receipt', inputs.invokeWriterReceiptBytes],
    ['invoke-writer-result', inputs.invokeWriterResultBytes],
    ['verify-anchor-claim', inputs.verifyAnchorClaimBytes],
    ['verify-anchor-receipt', inputs.verifyAnchorReceiptBytes],
    ['verify-anchor-result', inputs.verifyAnchorResultBytes],
  ].map(([role, bytes]) => ({ role, sha256: sha256(bytes) }));
}

export function buildPrivilegedTerminalPassMarker({ context, paths, ...inputs } = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  validateTerminalPassContext(context, code);
  exactTerminalPassPaths(paths, context);
  validateTerminalPassInputs(inputs, code);
  return {
    schema_version: 1, purpose: 'CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1',
    authority_sha: context.authority.commit, generations: structuredClone(context.generations),
    controller_sha256: context.authority.components.controller.sha256,
    launcher_sha256: context.authority.components.launcher.sha256,
    privileged_authority_sha256: sha256(inputs.authorityReceiptBytes),
    journal_frame_sha256: sha256(inputs.journalFrameBytes),
    journal_frame_byte_length: inputs.journalFrameBytes.length,
    complete_event_sha256: sha256(inputs.completeEventBytes),
    stdout_sha256: sha256(inputs.stdoutBytes), stdout_byte_length: inputs.stdoutBytes.length,
    stderr_sha256: sha256(inputs.stderrBytes), stderr_byte_length: inputs.stderrBytes.length,
    terminal_settlement_sha256: sha256(inputs.settlementBytes),
    complete_result_sha256: sha256(inputs.completeBytes),
    complete_final_scan_sha256: sha256(inputs.completeFinalScanBytes),
    pre_anchor_sha256: sha256(inputs.preAnchorBytes),
    writer_output_sha256: sha256(inputs.writerOutputBytes),
    terminal_final_scan_sha256: sha256(inputs.terminalFinalScanBytes),
    terminal_phase_objects_sha256: sha256(canonicalJson(terminalPhaseObjectRoots(inputs))),
    paths: terminalPassPathHashes(paths), terminal_state: 'TERMINAL_PASS',
    receipt_is_commit_marker: true, normal_executor_authorized: false, raw_values: false,
  };
}

export function validatePrivilegedTerminalPassMarker({ marker, context, paths, ...inputs } = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  exactKeys(marker, [
    'authority_sha', 'complete_event_sha256', 'complete_final_scan_sha256',
    'complete_result_sha256', 'controller_sha256', 'generations',
    'journal_frame_byte_length', 'journal_frame_sha256', 'launcher_sha256',
    'normal_executor_authorized', 'paths', 'privileged_authority_sha256', 'purpose',
    'pre_anchor_sha256',
    'raw_values', 'receipt_is_commit_marker', 'schema_version', 'stderr_byte_length',
    'stderr_sha256', 'stdout_byte_length', 'stdout_sha256', 'terminal_final_scan_sha256',
    'terminal_phase_objects_sha256', 'terminal_settlement_sha256', 'terminal_state',
    'writer_output_sha256',
  ], code);
  const expected = buildPrivilegedTerminalPassMarker({ context, paths, ...inputs });
  if (!canonicalJson(marker).equals(canonicalJson(expected))) fail(code);
  return true;
}

function parseTerminalRootObject(bytes, code) {
  try {
    const value = JSON.parse(bytes.toString('utf8'));
    if (!isPlainObject(value)) fail(code);
    return value;
  } catch { fail(code); }
}

function validateTerminalFinalScanRoot(receipt, context) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  exactKeys(receipt, [
    'authority_sha', 'input_byte_length', 'input_sha256', 'purpose', 'raw_values',
    'scan_results', 'schema_version', 'surface_roles', 'terminal_generation_id',
  ], code);
  const expectedRoles = [
    'process-argv', 'controller-journal', 'controller-stdout', 'controller-stderr',
    'terminal-attachments', 'simulator-xcresult', 'runtime-environment',
    'writer-output', 'terminal-settlement',
  ];
  requireSha(receipt.input_sha256, code);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_TERMINAL_FINAL_SCAN_V1'
      || receipt.authority_sha !== context.authority.commit
      || receipt.terminal_generation_id !== context.generations.terminal
      || !Number.isInteger(receipt.input_byte_length) || receipt.input_byte_length < 1
      || receipt.raw_values !== false
      || !canonicalJson(receipt.surface_roles).equals(canonicalJson(expectedRoles))
      || !Array.isArray(receipt.scan_results) || receipt.scan_results.length !== TERMINAL_SCAN_IDS.length) fail(code);
  for (let index = 0; index < TERMINAL_SCAN_IDS.length; index += 1) {
    exactKeys(receipt.scan_results[index], ['id', 'match_count'], code);
    if (receipt.scan_results[index].id !== TERMINAL_SCAN_IDS[index]
        || receipt.scan_results[index].match_count !== 0) fail(code);
  }
}

function validateObservedTerminalTarget(target, expectedPath, expectedBytes, observation, code) {
  if (target.path !== expectedPath || target.path_sha256 !== sha256(Buffer.from(expectedPath))
      || target.state !== 'PRESENT' || target.sha256 !== sha256(expectedBytes)) fail(code);
  if (observation) {
    if (target.identity_sha256 !== observation.identity_sha256
        || !canonicalJson(target.metadata).equals(canonicalJson(observation.metadata))) fail(code);
  }
}

export function validatePrivilegedPreAnchor(record, {
  context, paths, authorityReceipt, expected,
} = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  validateTerminalPassContext(context, code);
  exactTerminalPassPaths(paths, context);
  exactKeys(record, [
    'append_only', 'authority_manifest_sha256', 'authority_sha', 'authority_tree',
    'bootstrap_claim_sha256', 'claim_result_chain_sha256', 'components', 'created_at_utc',
    'evidence_chain_sha256', 'external_authority_roots', 'external_authority_roots_sha256',
    'generations', 'important_finding_ids', 'local_bundle_sha256', 'no_clobber',
    'phase_target_roots', 'phase_target_roots_sha256', 'privilege_mode',
    'privileged_claim_sha256', 'purpose', 'raw_values', 'remote_bundle_sha256',
    'scan_ids', 'scan_receipts', 'schema_version', 'secret_read',
    'simulator_gate_sha256', 'simulator_install_sha256', 'ssh_provenance_sha256',
    'terminal_settlement_contracts_sha256', 'terminal_state', 'writer_authority_path_sha256',
    'writer_binary_sha256', 'writer_signature_sha256', 'writer_source_sha256',
  ], code);
  exactKeys(expected, [
    'authorityManifestSha256', 'authorityTree', 'bootstrapClaimSha256',
    'claimResultChainSha256', 'components', 'createdAtUtc', 'evidenceChainSha256',
    'externalAuthorityRoots', 'generations', 'localBundleSha256', 'phaseTargetRoots',
    'privilegedClaimSha256', 'remoteBundleSha256', 'scanReceipts',
    'simulatorGateSha256', 'simulatorInstallSha256', 'sshProvenanceSha256',
    'terminalSettlementContractsSha256', 'writerAuthorityPathSha256',
    'writerBinarySha256', 'writerSignatureSha256', 'writerSourceSha256',
  ], code);
  if (!isPlainObject(authorityReceipt)
      || record.schema_version !== 1 || record.purpose !== 'CI3_PRE_TERMINAL_ANCHOR_V1'
      || record.authority_sha !== context.authority.commit
      || record.authority_tree !== expected.authorityTree
      || record.authority_manifest_sha256 !== expected.authorityManifestSha256
      || !canonicalJson(record.components).equals(canonicalJson(expected.components))
      || record.writer_source_sha256 !== expected.writerSourceSha256
      || record.writer_binary_sha256 !== expected.writerBinarySha256
      || record.writer_signature_sha256 !== expected.writerSignatureSha256
      || !canonicalJson(record.generations).equals(canonicalJson(expected.generations))
      || record.bootstrap_claim_sha256 !== expected.bootstrapClaimSha256
      || record.claim_result_chain_sha256 !== expected.claimResultChainSha256
      || record.remote_bundle_sha256 !== expected.remoteBundleSha256
      || record.local_bundle_sha256 !== expected.localBundleSha256
      || record.ssh_provenance_sha256 !== expected.sshProvenanceSha256
      || record.simulator_gate_sha256 !== expected.simulatorGateSha256
      || record.simulator_install_sha256 !== expected.simulatorInstallSha256
      || record.writer_authority_path_sha256 !== sha256(Buffer.from(paths.privilegedAuthority))
      || record.writer_authority_path_sha256 !== expected.writerAuthorityPathSha256
      || record.privileged_claim_sha256 !== expected.privilegedClaimSha256
      || record.evidence_chain_sha256 !== expected.evidenceChainSha256
      || !canonicalJson(record.external_authority_roots)
        .equals(canonicalJson(expected.externalAuthorityRoots))
      || !canonicalJson(record.phase_target_roots).equals(canonicalJson(expected.phaseTargetRoots))
      || !canonicalJson(record.scan_receipts).equals(canonicalJson(expected.scanReceipts))
      || record.terminal_settlement_contracts_sha256
        !== expected.terminalSettlementContractsSha256
      || record.terminal_state !== 'PENDING_VERIFICATION'
      || !Number.isFinite(Date.parse(record.created_at_utc)) || !record.created_at_utc.endsWith('Z')
      || record.created_at_utc !== expected.createdAtUtc
      || record.raw_values !== false || record.secret_read !== false
      || record.privilege_mode !== 'MACOS_ROOT_SINGLE_ADMIN_PROMPT'
      || record.append_only !== true || record.no_clobber !== true) fail(code);
  for (const field of [
    'authority_manifest_sha256', 'bootstrap_claim_sha256', 'claim_result_chain_sha256',
    'remote_bundle_sha256', 'local_bundle_sha256', 'ssh_provenance_sha256',
    'simulator_gate_sha256', 'simulator_install_sha256', 'writer_authority_path_sha256',
    'writer_source_sha256', 'writer_binary_sha256', 'writer_signature_sha256',
    'privileged_claim_sha256', 'evidence_chain_sha256',
    'external_authority_roots_sha256', 'phase_target_roots_sha256',
    'terminal_settlement_contracts_sha256',
  ]) requireSha(record[field], code);
  const externalRoles = [
    'operation-authority-root', 'vps-pass-root', 'vps-issuer-authority-root',
    'human-authorization-root', 'publisher-input-manifest-root',
    'ssh-trust-descriptor', 'ssh-public-key', 'ssh-public-key-fingerprint',
  ];
  if (!Array.isArray(record.external_authority_roots)
      || record.external_authority_roots.length !== externalRoles.length) fail(code);
  for (let index = 0; index < externalRoles.length; index += 1) {
    const entry = record.external_authority_roots[index];
    exactKeys(entry, ['role', 'sha256'], code);
    requireSha(entry.sha256, code);
    if (entry.role !== externalRoles[index]) fail(code);
  }
  if (record.external_authority_roots_sha256 !== sha256(canonicalJson(record.external_authority_roots))) fail(code);
  if (!Array.isArray(record.phase_target_roots)
      || record.phase_target_roots.length !== CONTROLLER_EVIDENCE_PHASES.length) fail(code);
  for (let index = 0; index < CONTROLLER_EVIDENCE_PHASES.length; index += 1) {
    const entry = record.phase_target_roots[index];
    exactKeys(entry, ['phase', 'receipt_sha256', 'targets_sha256'], code);
    requireSha(entry.receipt_sha256, code);
    requireSha(entry.targets_sha256, code);
    if (entry.phase !== CONTROLLER_EVIDENCE_PHASES[index]) fail(code);
  }
  if (record.phase_target_roots_sha256 !== sha256(canonicalJson(record.phase_target_roots))
      || !canonicalJson(record.scan_ids).equals(canonicalJson(TERMINAL_SCAN_IDS))
      || !Array.isArray(record.scan_receipts)
      || record.scan_receipts.length !== TERMINAL_SCAN_IDS.length) fail(code);
  for (let index = 0; index < TERMINAL_SCAN_IDS.length; index += 1) {
    const entry = record.scan_receipts[index];
    exactKeys(entry, ['id', 'sha256'], code);
    requireSha(entry.sha256, code);
    if (entry.id !== TERMINAL_SCAN_IDS[index]) fail(code);
  }
  if (!canonicalJson(record.important_finding_ids)
    .equals(canonicalJson(IMPORTANT_FINDINGS.map(({ id }) => id)))) fail(code);
  if (authorityReceipt.authority_sha !== record.authority_sha
      || authorityReceipt.terminal_generation_id !== record.generations.terminal
      || authorityReceipt.writer_source_sha256 !== record.writer_source_sha256
      || authorityReceipt.writer_binary_sha256 !== record.writer_binary_sha256
      || authorityReceipt.writer_signature_sha256 !== record.writer_signature_sha256
      || authorityReceipt.privileged_claim_sha256 !== record.privileged_claim_sha256
      || authorityReceipt.authority_path_sha256 !== record.writer_authority_path_sha256
      || authorityReceipt.anchor_path_sha256 !== sha256(Buffer.from(paths.preAnchor))) fail(code);
  return true;
}

export function validateTerminalSemanticEvidenceReceipt(receipt, {
  context, authorityExpected, preAnchorExpected,
} = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  validateTerminalPassContext(context, code);
  exactKeys(receipt, [
    'authority_sha', 'evidence_count', 'evidence_roles_sha256', 'evidence_roots',
    'evidence_roots_sha256', 'generations', 'purpose', 'raw_values',
    'run_scans_result_sha256', 'scan_receipt_count', 'scan_receipt_roots',
    'scan_receipt_roots_sha256', 'schema_version', 'semantic_roots',
    'semantic_roots_sha256', 'terminal_manifest_sha256',
    'terminal_settlement_contracts', 'terminal_settlement_contracts_sha256',
    'writer_binary_sha256', 'writer_executable_identity_sha256',
    'writer_signature_sha256',
  ], code);
  if (!isPlainObject(authorityExpected)
      || (preAnchorExpected !== null && !isPlainObject(preAnchorExpected))) fail(code);
  const expectedContracts = buildTerminalSettlementContracts({
    authoritySha: context.authority.commit,
    controllerGenerationId: context.generations.controller,
    terminalGenerationId: context.generations.terminal,
    runScansResultSha256: receipt.run_scans_result_sha256,
  });
  if (receipt.schema_version !== 1
      || receipt.purpose !== 'CI3_TERMINAL_SEMANTIC_VALIDATION_RECEIPT_V1'
      || receipt.authority_sha !== context.authority.commit
      || !canonicalJson(receipt.generations).equals(canonicalJson(context.generations))
      || receipt.terminal_manifest_sha256 !== authorityExpected.terminalManifestSha256
      || receipt.writer_binary_sha256 !== authorityExpected.writerBinarySha256
      || receipt.writer_signature_sha256 !== authorityExpected.writerSignatureSha256
      || receipt.writer_executable_identity_sha256
        !== authorityExpected.writerExecutableIdentitySha256
      || receipt.evidence_count !== TERMINAL_MANIFEST_EVIDENCE_ROLES.length
      || receipt.evidence_roles_sha256
        !== sha256(Buffer.from(TERMINAL_MANIFEST_EVIDENCE_ROLES.join('\n')))
      || receipt.scan_receipt_count !== TERMINAL_SCAN_IDS.length
      || receipt.raw_values !== false
      || !canonicalJson(receipt.terminal_settlement_contracts)
        .equals(canonicalJson(expectedContracts))
      || receipt.terminal_settlement_contracts_sha256 !== sha256(canonicalJson(expectedContracts))) {
    fail(code);
  }
  requireSha(receipt.run_scans_result_sha256, code);
  for (const field of [
    'evidence_roots_sha256', 'scan_receipt_roots_sha256', 'semantic_roots_sha256',
    'terminal_manifest_sha256', 'terminal_settlement_contracts_sha256',
    'writer_binary_sha256', 'writer_executable_identity_sha256', 'writer_signature_sha256',
  ]) requireSha(receipt[field], code);
  if (!Array.isArray(receipt.evidence_roots)
      || receipt.evidence_roots.length !== TERMINAL_MANIFEST_EVIDENCE_ROLES.length) fail(code);
  for (let index = 0; index < TERMINAL_MANIFEST_EVIDENCE_ROLES.length; index += 1) {
    const entry = receipt.evidence_roots[index];
    exactKeys(entry, ['role', 'sha256'], code);
    requireSha(entry.sha256, code);
    if (entry.role !== TERMINAL_MANIFEST_EVIDENCE_ROLES[index]) fail(code);
  }
  if (receipt.evidence_roots_sha256 !== sha256(canonicalJson(receipt.evidence_roots))) fail(code);
  if (!Array.isArray(receipt.scan_receipt_roots)
      || receipt.scan_receipt_roots.length !== TERMINAL_SCAN_IDS.length) fail(code);
  for (let index = 0; index < TERMINAL_SCAN_IDS.length; index += 1) {
    const entry = receipt.scan_receipt_roots[index];
    exactKeys(entry, ['id', 'sha256'], code);
    requireSha(entry.sha256, code);
    if (entry.id !== TERMINAL_SCAN_IDS[index]) fail(code);
  }
  if (receipt.scan_receipt_roots_sha256 !== sha256(canonicalJson(receipt.scan_receipt_roots))) fail(code);
  const semantic = receipt.semantic_roots;
  exactKeys(semantic, [
    'authority_manifest_sha256', 'bootstrap_claim_sha256', 'claim_result_chain_sha256',
    'evidence_chain_sha256', 'external_authority_roots', 'local_bundle_sha256',
    'phase_target_roots', 'remote_bundle_sha256', 'scan_receipts',
    'simulator_gate_sha256', 'simulator_install_sha256', 'ssh_provenance_sha256',
    'terminal_settlement_contracts_sha256',
  ], code);
  for (const field of [
    'authority_manifest_sha256', 'bootstrap_claim_sha256', 'claim_result_chain_sha256',
    'evidence_chain_sha256', 'local_bundle_sha256', 'remote_bundle_sha256',
    'simulator_gate_sha256', 'simulator_install_sha256', 'ssh_provenance_sha256',
    'terminal_settlement_contracts_sha256',
  ]) requireSha(semantic[field], code);
  if (receipt.semantic_roots_sha256 !== sha256(canonicalJson(semantic))
      || !canonicalJson(semantic.scan_receipts).equals(canonicalJson(receipt.scan_receipt_roots))
      || semantic.terminal_settlement_contracts_sha256
        !== receipt.terminal_settlement_contracts_sha256) fail(code);
  if (preAnchorExpected !== null
      && (semantic.authority_manifest_sha256 !== preAnchorExpected.authorityManifestSha256
        || semantic.bootstrap_claim_sha256 !== preAnchorExpected.bootstrapClaimSha256
        || semantic.claim_result_chain_sha256 !== preAnchorExpected.claimResultChainSha256
        || semantic.remote_bundle_sha256 !== preAnchorExpected.remoteBundleSha256
        || semantic.local_bundle_sha256 !== preAnchorExpected.localBundleSha256
        || semantic.ssh_provenance_sha256 !== preAnchorExpected.sshProvenanceSha256
        || semantic.simulator_gate_sha256 !== preAnchorExpected.simulatorGateSha256
        || semantic.simulator_install_sha256 !== preAnchorExpected.simulatorInstallSha256
        || semantic.evidence_chain_sha256 !== preAnchorExpected.evidenceChainSha256
        || !canonicalJson(semantic.external_authority_roots)
          .equals(canonicalJson(preAnchorExpected.externalAuthorityRoots))
        || !canonicalJson(semantic.phase_target_roots)
          .equals(canonicalJson(preAnchorExpected.phaseTargetRoots))
        || !canonicalJson(semantic.scan_receipts)
          .equals(canonicalJson(preAnchorExpected.scanReceipts))
        || semantic.terminal_settlement_contracts_sha256
          !== preAnchorExpected.terminalSettlementContractsSha256)) fail(code);
  return Object.freeze({
    runScansResultSha256: receipt.run_scans_result_sha256,
    terminalSettlementContracts: structuredClone(expectedContracts),
  });
}

export function validateTerminalManifestEvidenceWithCanonicalWriter({
  writerPath, manifestPath, context, expectedManifestSha256,
  expectedWriterBinarySha256, expectedWriterSignatureSha256,
  expectedWriterIdentitySha256,
} = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  validateTerminalPassContext(context, code);
  if (!path.isAbsolute(writerPath ?? '') || writerPath.includes('/../')
      || !path.isAbsolute(manifestPath ?? '') || manifestPath.includes('/../')) fail(code);
  for (const value of [
    expectedManifestSha256, expectedWriterBinarySha256,
    expectedWriterSignatureSha256, expectedWriterIdentitySha256,
  ]) requireSha(value, code);
  const executed = spawnSync(writerPath, [
    '--validate-manifest', manifestPath, context.authority.commit,
    context.generations.remote, context.generations.controller,
    context.generations.simulator, context.generations.terminal,
  ], {
    encoding: 'utf8', timeout: 60000, maxBuffer: 1024 * 1024,
    env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
  });
  if (executed.error || executed.signal !== null || executed.status !== 0
      || executed.stderr !== '' || !executed.stdout.endsWith('\n')
      || executed.stdout.slice(0, -1).includes('\n')) fail(code);
  let receipt;
  try { receipt = JSON.parse(executed.stdout); } catch { fail(code); }
  validateTerminalSemanticEvidenceReceipt(receipt, {
    context,
    authorityExpected: {
      terminalManifestSha256: expectedManifestSha256,
      writerBinarySha256: expectedWriterBinarySha256,
      writerSignatureSha256: expectedWriterSignatureSha256,
      writerExecutableIdentitySha256: expectedWriterIdentitySha256,
    },
    preAnchorExpected: null,
  });
  return receipt;
}

export function validatePrivilegedTerminalTransitiveRoots({
  context, paths, authorityExpected, preAnchorExpected, semanticEvidenceReceipt,
  rootObservations = null, ...inputs
} = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  validateTerminalPassContext(context, code);
  exactTerminalPassPaths(paths, context);
  validateTerminalPassInputs(inputs, code);
  if (rootObservations !== null) {
    exactKeys(rootObservations, PRIVILEGED_TERMINAL_PATH_KEYS.filter((key) => key !== 'marker'), code);
  }
  const authority = parseTerminalRootObject(inputs.authorityReceiptBytes, code);
  const preAnchor = parseTerminalRootObject(inputs.preAnchorBytes, code);
  const settlement = parseTerminalRootObject(inputs.settlementBytes, code);
  const writerOutput = parseTerminalRootObject(inputs.writerOutputBytes, code);
  const terminalFinalScan = parseTerminalRootObject(inputs.terminalFinalScanBytes, code);
  const complete = parseTerminalRootObject(inputs.completeBytes, code);
  const completeFinalScan = parseTerminalRootObject(inputs.completeFinalScanBytes, code);
  const completeEvent = parseTerminalRootObject(inputs.completeEventBytes, code);
  try { validatePrivilegedWriterAuthorityReceipt(authority, authorityExpected); } catch { fail(code); }
  const semanticEvidence = validateTerminalSemanticEvidenceReceipt(semanticEvidenceReceipt, {
    context, authorityExpected, preAnchorExpected,
  });
  validatePrivilegedPreAnchor(preAnchor, {
    context, paths, authorityReceipt: authority, expected: preAnchorExpected,
  });
  try { validateTerminalSettlementReceipt(settlement); } catch { fail(code); }
  if (settlement.authority_sha !== context.authority.commit
      || !canonicalJson(settlement.generations).equals(canonicalJson(context.generations))
      || settlement.pre_anchor_sha256 !== sha256(inputs.preAnchorBytes)
      || settlement.settlement_authority_sha256 !== sha256(inputs.authorityReceiptBytes)
      || settlement.terminal_settlement_contracts_sha256
        !== preAnchor.terminal_settlement_contracts_sha256) fail(code);
  exactKeys(writerOutput, [
    'authority_sha', 'pre_anchor_sha256', 'purpose', 'raw_values', 'schema_version',
    'terminal_generation_id', 'terminal_settlement_sha256',
  ], code);
  if (writerOutput.schema_version !== 1 || writerOutput.purpose !== 'CI3_PRIVILEGED_WRITER_OUTPUT_V1'
      || writerOutput.authority_sha !== context.authority.commit
      || writerOutput.terminal_generation_id !== context.generations.terminal
      || writerOutput.pre_anchor_sha256 !== sha256(inputs.preAnchorBytes)
      || writerOutput.terminal_settlement_sha256 !== sha256(inputs.settlementBytes)
      || writerOutput.raw_values !== false) fail(code);
  validateTerminalFinalScanRoot(terminalFinalScan, context);
  try {
    validateTerminalCompleteResult(complete, {
      settlementBytes: inputs.settlementBytes, finalScanBytes: inputs.terminalFinalScanBytes,
    });
    validateTerminalCompleteFinalScan(completeFinalScan, inputs.completeBytes);
  } catch { fail(code); }
  if (complete.authority_sha !== context.authority.commit
      || !canonicalJson(complete.generations).equals(canonicalJson(context.generations))
      || complete.pre_anchor_sha256 !== sha256(inputs.preAnchorBytes)
      || completeFinalScan.authority_sha !== context.authority.commit
      || completeFinalScan.terminal_generation_id !== context.generations.terminal) fail(code);
  exactKeys(completeEvent, ['event', 'result', 'result_sha256', 'state'], code);
  exactKeys(completeEvent.result, ['terminal_commit_contract_sha256'], code);
  requireSha(completeEvent.result.terminal_commit_contract_sha256, code);
  if (completeEvent.event !== 'COMPLETE' || completeEvent.state !== 'COMPLETE'
      || completeEvent.result_sha256 !== sha256(canonicalJson(completeEvent.result))
      || !inputs.journalFrameBytes.includes(inputs.completeEventBytes)) fail(code);

  const phaseRoots = [];
  let predecessor = semanticEvidence.runScansResultSha256;
  for (const [phaseIndex, [phase, prefix]] of [
    ['INVOKE_WRITER', 'invokeWriter'], ['VERIFY_ANCHOR', 'verifyAnchor'],
  ].entries()) {
    const phaseInputs = {
      claim: inputs[`${prefix}ClaimBytes`],
      receipt: inputs[`${prefix}ReceiptBytes`],
      result: inputs[`${prefix}ResultBytes`],
    };
    const claim = parseTerminalRootObject(phaseInputs.claim, code);
    const receipt = parseTerminalRootObject(phaseInputs.receipt, code);
    const result = parseTerminalRootObject(phaseInputs.result, code);
    const roots = {
      claim_sha256: sha256(phaseInputs.claim), receipt_sha256: sha256(phaseInputs.receipt),
      result_sha256: sha256(phaseInputs.result),
    };
    exactKeys(claim, [
      'attempt', 'authority_sha', 'contract_sha256', 'controller_generation_id', 'phase',
      'predecessor_result_sha256', 'purpose', 'raw_values', 'retry', 'schema_version',
    ], code);
    exactKeys(receipt, [
      'claim_sha256', 'observation', 'phase', 'purpose', 'raw_values', 'result',
      'result_sha256', 'schema_version',
    ], code);
    exactKeys(result, [
      'claim_sha256', 'phase', 'physical_observation_sha256', 'purpose', 'raw_values',
      'receipt_sha256', 'schema_version', 'terminal_state',
    ], code);
    const expectedContract = semanticEvidence.terminalSettlementContracts[phaseIndex];
    requireSha(claim.contract_sha256, code);
    requireSha(claim.predecessor_result_sha256, code);
    if (claim.schema_version !== 1 || claim.purpose !== 'CI3_MAC_PHASE_CLAIM_V1'
        || claim.phase !== phase || claim.authority_sha !== context.authority.commit
        || claim.controller_generation_id !== context.generations.controller
        || claim.attempt !== 1 || claim.retry !== false || claim.raw_values !== false
        || claim.predecessor_result_sha256 !== predecessor
        || claim.contract_sha256 !== sha256(canonicalJson(expectedContract))
        || receipt.schema_version !== 1 || receipt.purpose !== 'CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1'
        || receipt.phase !== phase || receipt.claim_sha256 !== roots.claim_sha256
        || receipt.result_sha256 !== sha256(canonicalJson(receipt.result)) || receipt.raw_values !== false
        || result.schema_version !== 1 || result.purpose !== 'CI3_MAC_PHASE_RESULT_V1'
        || result.phase !== phase || result.claim_sha256 !== roots.claim_sha256
        || result.receipt_sha256 !== roots.receipt_sha256
        || result.physical_observation_sha256 !== receipt.observation?.observation_sha256
        || result.terminal_state !== 'PHASE_SETTLED' || result.raw_values !== false) fail(code);
    try { validatePhysicalEffectObservation(receipt.observation, phase); } catch { fail(code); }
    const expectedTriple = phase === 'INVOKE_WRITER' ? settlement.invoke_writer : settlement.verify_anchor;
    if (!canonicalJson(expectedTriple).equals(canonicalJson(roots))) fail(code);
    if (phase === 'INVOKE_WRITER') {
      exactKeys(receipt.result, ['pre_anchor_sha256', 'raw_values', 'writer_transaction'], code);
      if (receipt.result.pre_anchor_sha256 !== sha256(inputs.preAnchorBytes)
          || receipt.result.writer_transaction !== 'SINGLE_PRIVILEGED_INVOCATION'
          || receipt.result.raw_values !== false || receipt.observation.targets.length !== 1) fail(code);
      validateObservedTerminalTarget(
        receipt.observation.targets[0], paths.preAnchor, inputs.preAnchorBytes,
        rootObservations?.preAnchor, code,
      );
    } else {
      exactKeys(receipt.result, ['pre_anchor_sha256', 'raw_values', 'readback_verified'], code);
      if (receipt.result.pre_anchor_sha256 !== sha256(inputs.preAnchorBytes)
          || receipt.result.readback_verified !== true || receipt.result.raw_values !== false
          || receipt.observation.targets.length !== 2) fail(code);
      validateObservedTerminalTarget(
        receipt.observation.targets[0], paths.preAnchor, inputs.preAnchorBytes,
        rootObservations?.preAnchor, code,
      );
      validateObservedTerminalTarget(
        receipt.observation.targets[1], paths.invokeWriterResult, inputs.invokeWriterResultBytes,
        rootObservations?.invokeWriterResult, code,
      );
    }
    phaseRoots.push({ phase, ...roots });
    predecessor = roots.result_sha256;
  }
  if (settlement.terminal_phase_graph_sha256 !== sha256(canonicalJson(phaseRoots))) fail(code);
  return true;
}

export function validatePrivilegedTerminalPassCorpus({ marker, ...corpus } = {}) {
  validatePrivilegedTerminalTransitiveRoots(corpus);
  validatePrivilegedTerminalPassMarker({ marker, ...corpus });
  return true;
}

export async function emitRetainedScannedTerminalBytes({
  filePath, expectedSha256, emit, scheduler = null,
} = {}) {
  const code = 'TERMINAL_TAIL';
  if (!path.isAbsolute(filePath ?? '') || typeof emit !== 'function') fail(code);
  requireSha(expectedSha256, code);
  const handle = await open(filePath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW).catch(() => fail(code));
  try {
    const before = await handle.stat({ bigint: true });
    if (!before.isFile() || before.nlink !== 1n || (before.mode & 0o777n) !== 0o600n) fail(code);
    const bytes = await handle.readFile();
    if (sha256(bytes) !== expectedSha256 || scanTerminalSurface('terminal-log', bytes).total !== 0) fail(code);
    await scheduler?.afterScan?.();
    const after = await handle.stat({ bigint: true });
    if (!canonicalJson(descriptorIdentity(before)).equals(canonicalJson(descriptorIdentity(after)))) fail(code);
    await emit(bytes);
    const final = await handle.stat({ bigint: true });
    if (!canonicalJson(descriptorIdentity(after)).equals(canonicalJson(descriptorIdentity(final)))) fail(code);
    return { sha256: expectedSha256, byte_length: bytes.length, raw_values: false };
  } finally { await handle.close(); }
}

export async function validatePublisher0BootstrapBoundary({ boundary, processState, chain } = {}) {
  const code = 'VPS_PUBLISHER0_BOOTSTRAP';
  if (!isPlainObject(boundary) || !isPlainObject(processState) || !Array.isArray(chain)) fail(code);
  exactKeys(boundary, [
    'allowed_environment', 'authority_manifest_path', 'authority_manifest_sha256',
    'authority_sha', 'bootstrap_generation_id', 'controller_path', 'controller_sha256',
    'descriptor_backend', 'issuer_receipt_sha256',
    'launch_attestation_path', 'launch_attestation_sha256', 'launcher_path', 'launcher_sha256',
    'materializer_mode', 'node_path', 'node_sha256', 'purpose', 'raw_values', 'root',
    'schema_version', 'user_checkout_executable',
  ], code);
  requireSha(boundary.authority_sha, code, [40]);
  if (!/^bootstrap-[a-f0-9]{64}$/.test(boundary.bootstrap_generation_id ?? '')) fail(code);
  const expectedRoot = `/var/lib/agentempp/ci3-publisher0-bootstrap/${boundary.authority_sha}/${boundary.bootstrap_generation_id}`;
  const runtimeRoot = `${expectedRoot}/runtime`;
  const expectedEnvironment = CLOSED_BOOTSTRAP_ENVIRONMENT;
  if (boundary.schema_version !== 1 || boundary.purpose !== 'CI3_VPS_PUBLISHER0_BOOTSTRAP_AUTHORITY_V2'
      || boundary.root !== expectedRoot || boundary.node_path !== `${expectedRoot}/runtime/node`
      || boundary.controller_path !== `${expectedRoot}/runtime/ci3-bridge-controller.mjs`
      || boundary.launcher_path !== `${runtimeRoot}/ci3-bridge-launcher.zsh`
      || boundary.launch_attestation_path !== `${runtimeRoot}/launch-attestation.json`
      || boundary.authority_manifest_path !== `${runtimeRoot}/authority-manifest.v1`
      || boundary.descriptor_backend !== 'NODE_CORE_PROC_FD_V1'
      || boundary.materializer_mode !== 'publish-vps-operation-authority-pass'
      || boundary.user_checkout_executable !== false || boundary.raw_values !== false
      || !canonicalJson(boundary.allowed_environment).equals(canonicalJson(expectedEnvironment))) fail(code);
  for (const value of [
    boundary.node_sha256, boundary.controller_sha256, boundary.launcher_sha256,
    boundary.launch_attestation_sha256, boundary.authority_manifest_sha256,
    boundary.issuer_receipt_sha256,
  ]) requireSha(value, code);
  exactKeys(processState, [
    'authority_manifest_path', 'authority_manifest_sha256', 'controller_sha256',
    'descriptor_backend', 'environment', 'exec_path',
    'launch_attestation_path', 'launch_attestation_sha256', 'launcher_path',
    'launcher_sha256', 'node_sha256', 'script_path',
  ], code);
  if (processState.exec_path !== boundary.node_path || processState.script_path !== boundary.controller_path
      || processState.node_sha256 !== boundary.node_sha256
      || processState.controller_sha256 !== boundary.controller_sha256
      || processState.launcher_path !== boundary.launcher_path
      || processState.launcher_sha256 !== boundary.launcher_sha256
      || processState.launch_attestation_path !== boundary.launch_attestation_path
      || processState.launch_attestation_sha256 !== boundary.launch_attestation_sha256
      || processState.authority_manifest_path !== boundary.authority_manifest_path
      || processState.authority_manifest_sha256 !== boundary.authority_manifest_sha256
      || processState.descriptor_backend !== boundary.descriptor_backend
      || !canonicalJson(processState.environment).equals(canonicalJson(expectedEnvironment))) fail(code);
  const expectedPaths = runtimeRoot.split('/').filter(Boolean).map((_, index, names) => `/${names.slice(0, index + 1).join('/')}`);
  if (chain.length !== expectedPaths.length) fail(code);
  for (let index = 0; index < chain.length; index += 1) {
    const entry = chain[index];
    exactKeys(entry, ['gid', 'identity_sha256', 'immutable', 'mode', 'nlink', 'path', 'symlink', 'type', 'uid'], code);
    requireSha(entry.identity_sha256, code);
    if (entry.path !== expectedPaths[index] || entry.uid !== 0 || entry.gid !== 0
        || entry.type !== 'directory' || entry.symlink !== false || entry.nlink < 1
        || entry.mode !== (index >= chain.length - 2 ? 0o555 : 0o755)
        || (index >= 3 && entry.immutable !== true)) fail(code);
  }
  return true;
}

async function assertPublisher0FixedProcessBoundary() {
  const code = 'VPS_PUBLISHER0_BOOTSTRAP';
  const match = /^\/var\/lib\/agentempp\/ci3-publisher0-bootstrap\/([a-f0-9]{40})\/(bootstrap-[a-f0-9]{64})\/runtime\/ci3-bridge-controller\.mjs$/.exec(SCRIPT_PATH);
  if (!match) fail(code);
  const root = path.dirname(path.dirname(SCRIPT_PATH));
  const boundaryPath = path.join(root, 'publisher0-bootstrap-authority.json');
  const boundaryBytes = await readVpsRootImmutableFile(boundaryPath, 0o444, code);
  let boundary;
  try { boundary = JSON.parse(boundaryBytes.toString('utf8')); } catch { fail(code); }
  const issuerPath = `/etc/agentempp/ci3-publisher0-issuers/${match[1]}.json`;
  const issuerBytes = await readVpsRootImmutableFile(issuerPath, 0o444, code);
  if (sha256(issuerBytes) !== boundary.issuer_receipt_sha256) fail(code);
  const componentObservations = {};
  for (const [role, filePath, mode] of [
    ['node', boundary.node_path, 0o555], ['controller', boundary.controller_path, 0o555],
    ['launcher', boundary.launcher_path, 0o555],
    ['launch_attestation', boundary.launch_attestation_path, 0o444],
    ['authority_manifest', boundary.authority_manifest_path, 0o444],
  ]) {
    componentObservations[role] = await readVpsRootImmutableFile(filePath, mode, code, { returnObservation: true });
  }
  if (sha256(componentObservations.node.bytes) !== boundary.node_sha256
      || sha256(componentObservations.controller.bytes) !== boundary.controller_sha256
      || sha256(componentObservations.launcher.bytes) !== boundary.launcher_sha256
      || sha256(componentObservations.launch_attestation.bytes) !== boundary.launch_attestation_sha256
      || sha256(componentObservations.authority_manifest.bytes) !== boundary.authority_manifest_sha256) fail(code);
  const chain = componentObservations.controller.directoryChain.slice(1);
  const environment = Object.fromEntries(Object.entries(process.env).sort(([left], [right]) => left.localeCompare(right)));
  await validatePublisher0BootstrapBoundary({
    boundary,
    processState: {
      exec_path: process.execPath, script_path: SCRIPT_PATH, environment,
      launcher_path: boundary.launcher_path,
      launch_attestation_path: boundary.launch_attestation_path,
      authority_manifest_path: boundary.authority_manifest_path,
      descriptor_backend: 'NODE_CORE_PROC_FD_V1',
      node_sha256: sha256(componentObservations.node.bytes),
      controller_sha256: sha256(componentObservations.controller.bytes),
      launcher_sha256: sha256(componentObservations.launcher.bytes),
      launch_attestation_sha256: sha256(componentObservations.launch_attestation.bytes),
      authority_manifest_sha256: sha256(componentObservations.authority_manifest.bytes),
    },
    chain,
  });
  return boundary;
}

export function scannerSchemaSha256(id) {
  const contract = SCAN_SURFACE_CONTRACTS[id];
  const patterns = SCAN_CLASS_PATTERNS[id];
  if (!contract || !patterns) fail('TERMINAL_SCAN_SET');
  return sha256(canonicalJson({
    ...contract,
    patterns: Object.fromEntries(Object.entries(patterns).map(([name, expression]) => [name, expression.source])),
    generic_patterns: Object.fromEntries(Object.entries(GENERIC_SCAN_PATTERNS).map(([name, expression]) => [name, expression.source])),
    implementation: 'CI3_TERMINAL_SCANNER_V2',
  }));
}

export function validateScanSurfaceAuthority(scans, authoritySha = null, controllerSha256 = null) {
  const code = 'OPERATION_AUTHORITY';
  exactKeys(scans, TERMINAL_SCAN_IDS, code);
  if (authoritySha !== null) requireSha(authoritySha, code, [40]);
  if (controllerSha256 !== null) requireSha(controllerSha256, code);
  for (const id of TERMINAL_SCAN_IDS) {
    const descriptor = scans[id];
    exactKeys(descriptor, [
      'collector_version', 'contract_sha256', 'format', 'id', 'source_role',
      'tool_sha256',
    ], code);
    const contract = SCAN_SURFACE_CONTRACTS[id];
    if (descriptor.id !== id || descriptor.collector_version !== contract.collector_version
        || descriptor.format !== contract.format || descriptor.source_role !== contract.source_role
        || descriptor.contract_sha256 !== scannerSchemaSha256(id)) fail(code);
    requireSha(descriptor.tool_sha256, code);
    if (controllerSha256 !== null && descriptor.tool_sha256 !== controllerSha256) fail(code);
  }
  return true;
}

export function buildFinalScanSurfaceBytes({
  scanId, authoritySha, controllerGenerationId, terminalGenerationId, sourceRoots, sourceBytes,
  sourceObservation = null,
} = {}) {
  const code = 'TERMINAL_SCAN_SURFACE';
  const contract = SCAN_SURFACE_CONTRACTS[scanId];
  if (!contract) fail(code);
  requireSha(authoritySha, code, [40]);
  try {
    validateGenerationId(controllerGenerationId);
    validateGenerationId(terminalGenerationId);
  } catch { fail(code); }
  if (!Array.isArray(sourceRoots) || sourceRoots.length !== 1
      || !(Buffer.isBuffer(sourceBytes) || sourceBytes instanceof Uint8Array)) fail(code);
  const content = Buffer.from(sourceBytes);
  const scanResult = scanTerminalSurface(scanId, content);
  if (scanResult.total !== 0) fail('TERMINAL_SCAN_MATCH');
  const seen = new Set();
  for (const root of sourceRoots) {
    exactKeys(root, ['identity_sha256', 'role', 'sha256'], code);
    if (typeof root.role !== 'string' || !/^[a-z0-9-]+$/.test(root.role) || seen.has(root.role)) fail(code);
    requireSha(root.sha256, code);
    requireSha(root.identity_sha256, code);
    if (root.sha256 !== sha256(content)) fail(code);
    seen.add(root.role);
  }
  if (sourceObservation !== null) {
    if (!isPlainObject(sourceObservation)
        || sourceObservation.purpose !== 'CI3_TERMINAL_SCAN_SOURCE_OBSERVATION_V1'
        || sourceObservation.scan_id !== scanId
        || sourceObservation.source_semantics !== contract.source_semantics
        || !['PRESENT', 'ABSENT'].includes(sourceObservation.state)
        || sourceObservation.path_sha256 !== sha256(Buffer.from(sourceObservation.path ?? ''))) fail(code);
    if (sourceObservation.state === 'PRESENT') {
      if (sourceObservation.content_sha256 !== sha256(content)
          || sourceObservation.identity_sha256 !== sourceRoots[0].identity_sha256) fail(code);
    } else if (contract.required_state !== 'PRESENT_OR_PROVEN_ABSENT'
        || content.length !== 0 || sourceObservation.content_sha256 !== null
        || sourceObservation.absence_observation_sha256 !== sourceRoots[0].identity_sha256) fail(code);
  }
  return canonicalJson({
    schema_version: 1,
    purpose: 'CI3_FINAL_OPERATION_SCAN_SURFACE_V1',
    scan_id: scanId,
    collector_version: contract.collector_version,
    source_role: contract.source_role,
    authority_sha: authoritySha,
    controller_generation_id: controllerGenerationId,
    terminal_generation_id: terminalGenerationId,
    source_roots: structuredClone(sourceRoots),
    source_observation: sourceObservation === null ? null : structuredClone(sourceObservation),
    content_base64: content.toString('base64'),
    content_byte_length: content.length,
    content_sha256: sha256(content),
    raw_values: false,
  });
}

export async function observeTerminalScanSource({ scanId, root, sourcePath: suppliedSourcePath = null } = {}) {
  const code = 'TERMINAL_SCAN_SOURCE';
  const contract = SCAN_SURFACE_CONTRACTS[scanId];
  if (!contract || !path.isAbsolute(root ?? '')) fail(code);
  const sourcePath = suppliedSourcePath ?? path.join(root, contract.fixed_source_relative_path);
  if (!path.isAbsolute(sourcePath) || sourcePath.includes('/../')) fail(code);
  if (path.relative(root, sourcePath).startsWith('..')) fail(code);
  const parentPath = path.dirname(sourcePath);
  const parent = await lstat(parentPath, { bigint: true }).catch(() => fail(code));
  if (!parent.isDirectory() || parent.isSymbolicLink()
      || parent.uid !== BigInt(process.getuid()) || parent.gid !== BigInt(process.getgid())
      || (parent.mode & 0o777n) !== 0o700n) fail(code);
  const parentPhysical = metadataFromBigIntStat(parent, code);
  const parentMetadata = parentPhysical.metadata;
  const observed = await lstat(sourcePath).catch((error) => {
    if (error?.code === 'ENOENT') return null;
    throw error;
  });
  if (observed === null) {
    if (contract.required_state !== 'PRESENT_OR_PROVEN_ABSENT') fail(code);
    const body = {
      schema_version: 1, purpose: 'CI3_TERMINAL_SCAN_SOURCE_OBSERVATION_V1',
      scan_id: scanId, source_semantics: contract.source_semantics,
      state: 'ABSENT', path: sourcePath, path_sha256: sha256(Buffer.from(sourcePath)),
      content_sha256: null, identity_sha256: null, metadata: null, byte_range: null,
      parent_identity_sha256: parentPhysical.identity_sha256, raw_values: false,
    };
    return { ...body, absence_observation_sha256: sha256(canonicalJson(body)) };
  }
  const source = await readBoundLocalFile(sourcePath, { code, modes: [0o600] });
  return {
    schema_version: 1, purpose: 'CI3_TERMINAL_SCAN_SOURCE_OBSERVATION_V1',
    scan_id: scanId, source_semantics: contract.source_semantics,
    state: 'PRESENT', path: sourcePath, path_sha256: sha256(Buffer.from(sourcePath)),
    content_sha256: sha256(source.bytes), identity_sha256: physicalIdentitySha256(source.metadata),
    metadata: source.metadata, byte_range: { start: 0, end: source.bytes.length },
    parent_identity_sha256: parentPhysical.identity_sha256,
    absence_observation_sha256: null, raw_values: false,
  };
}

export async function materializeTerminalScanSources({ root, records, sourcePaths = {} } = {}) {
  const code = 'TERMINAL_SCAN_SOURCE';
  if (!path.isAbsolute(root ?? '') || !isPlainObject(records)) fail(code);
  const presentIds = TERMINAL_SCAN_IDS.filter((id) => id !== 'xcresult');
  exactKeys(records, presentIds, code);
  const rootObserved = await lstat(root).catch(() => fail(code));
  if (!rootObserved.isDirectory() || rootObserved.isSymbolicLink()
      || rootObserved.uid !== process.getuid() || rootObserved.gid !== process.getgid()
      || (rootObserved.mode & 0o777) !== 0o700) fail(code);
  const sourceRoot = path.join(root, 'final-sources');
  await ensurePrivateDirectory(sourceRoot);
  for (const id of presentIds) {
    const bytes = records[id];
    if (!(Buffer.isBuffer(bytes) || bytes instanceof Uint8Array)) fail(code);
    await writeOnceBytes(path.join(sourceRoot, `${id}.surface`), Buffer.from(bytes));
  }
  const observations = {};
  for (const id of TERMINAL_SCAN_IDS) observations[id] = await observeTerminalScanSource({
    scanId: id, root, sourcePath: sourcePaths[id] ?? null,
  });
  return observations;
}

export async function collectActualTerminalSurfaces({
  argv, historyPaths, terminalLogPaths, attachmentPaths, xcresultPath, runtime,
} = {}) {
  const code = 'TERMINAL_SCAN_SOURCE';
  if (!Array.isArray(argv) || !argv.every((value) => typeof value === 'string')
      || !isPlainObject(runtime)
      || !Array.isArray(historyPaths) || !Array.isArray(terminalLogPaths) || !Array.isArray(attachmentPaths)
      || ![...historyPaths, ...terminalLogPaths, ...attachmentPaths].every((value) => path.isAbsolute(value))
      || !path.isAbsolute(xcresultPath ?? '')) fail(code);
  const frame = async (scanId, paths) => {
    const records = [];
    for (const filePath of paths) {
      const observed = await readBoundLocalFile(filePath, { code, modes: [0o600] });
      if (scanTerminalSurface(scanId, observed.bytes).total !== 0) fail('TERMINAL_SCAN_MATCH');
      records.push({
        path_sha256: sha256(Buffer.from(filePath)),
        content_sha256: sha256(observed.bytes),
        content_byte_length: observed.bytes.length,
        content_base64: observed.bytes.toString('base64'),
      });
    }
    return canonicalJson(records);
  };
  const xcresult = await lstat(xcresultPath).catch((error) => {
    if (error?.code === 'ENOENT') return null;
    throw error;
  });
  let xcresultBytes = null;
  if (xcresult !== null) {
    if (!xcresult.isFile() || xcresult.isSymbolicLink() || xcresult.nlink !== 1
        || (xcresult.mode & 0o777) !== 0o600) fail(code);
    xcresultBytes = (await readBoundLocalFile(xcresultPath, { code, modes: [0o600] })).bytes;
  }
  return {
    argv: canonicalJson(argv),
    history: await frame('history', historyPaths),
    'terminal-log': await frame('terminal-log', terminalLogPaths),
    attachment: await frame('attachment', attachmentPaths),
    xcresult: xcresultBytes,
    runtime: canonicalJson(runtime),
  };
}

export function validateScanReceipt(receipt, expectedId) {
  const code = 'TERMINAL_SCAN_RECEIPT';
  exactKeys(receipt, [
    'authority_sha', 'command_sha256', 'controller_generation_id', 'finished_at',
    'counters', 'input_manifest_sha256', 'input_observations', 'input_stable_after_scan', 'local_bundle_sha256',
    'match_count', 'output_sha256', 'purpose', 'redaction', 'remote_generation_id',
    'result', 'scan_id', 'scanner_schema_sha256', 'schema_version', 'simulator_install_sha256',
    'simulator_generation_id', 'started_at', 'terminal_generation_id',
    'tool_sha256', 'worktree_diff_sha256',
  ], code);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_TERMINAL_SCAN_RECEIPT_V1' || receipt.scan_id !== expectedId || !TERMINAL_SCAN_IDS.includes(receipt.scan_id)) fail(code);
  requireSha(receipt.authority_sha, code, [40]);
  try {
    validateGenerationId(receipt.controller_generation_id);
    validateGenerationId(receipt.remote_generation_id);
    validateGenerationId(receipt.simulator_generation_id);
    validateGenerationId(receipt.terminal_generation_id);
  } catch {
    fail(code);
  }
  for (const field of ['command_sha256', 'input_manifest_sha256', 'local_bundle_sha256', 'output_sha256', 'simulator_install_sha256', 'tool_sha256', 'worktree_diff_sha256']) requireSha(receipt[field], code);
  requireSha(receipt.scanner_schema_sha256, code);
  if (receipt.scanner_schema_sha256 !== scannerSchemaSha256(expectedId)) fail(code);
  exactKeys(receipt.counters, ['jwt', 'pii', 'raw_destination', 'secret', 'token'], code);
  if (Object.values(receipt.counters).some((value) => !Number.isInteger(value) || value !== 0)) fail(code);
  if (!Array.isArray(receipt.input_observations) || receipt.input_observations.length !== 1) fail(code);
  for (const observation of receipt.input_observations) {
    exactKeys(observation, ['metadata', 'path', 'path_sha256', 'sha256'], code);
    if (!path.isAbsolute(observation.path)) fail(code);
    for (const field of ['path_sha256', 'sha256']) requireSha(observation[field], code);
    if (observation.path_sha256 !== sha256(Buffer.from(observation.path))) fail(code);
    exactKeys(observation.metadata, ['dev', 'gid', 'ino', 'mode', 'mtime_ns', 'nlink', 'size', 'uid'], code);
  }
  if (receipt.result !== 'CLEAN' || receipt.match_count !== 0 || receipt.redaction !== true || receipt.input_stable_after_scan !== true) fail(code);
  if (!Number.isFinite(Date.parse(receipt.started_at)) || !Number.isFinite(Date.parse(receipt.finished_at)) || Date.parse(receipt.finished_at) < Date.parse(receipt.started_at)) fail(code);
  return true;
}

export function buildTerminalManifest(input) {
  const code = 'TERMINAL_MANIFEST';
  requireSha(input.authoritySha, code, [40]);
  requireSha(input.authorityTree, code, [40]);
  requireSha(input.authorityManifestSha256, code);
  validateComponents(input.components, code);
  for (const value of Object.values(input.generations ?? {})) validateGenerationId(value);
  for (const field of [
    'bootstrapClaimSha256', 'readChainSha256', 'remoteBundleSha256',
    'localBundleSha256', 'sshProvenanceSha256', 'simulatorGateSha256',
    'installReceiptSha256', 'writerAuthorityPathSha256', 'writerSourceSha256',
    'writerBinarySha256', 'writerSignatureSha256', 'runScansResultSha256',
  ]) requireSha(input[field], code);
  if (input.writerSourceSha256 !== input.components.writer.sha256) fail(code);
  if (!Number.isFinite(Date.parse(input.createdAtUtc)) || !input.createdAtUtc.endsWith('Z')) fail(code);
  const evidenceRoles = TERMINAL_MANIFEST_EVIDENCE_ROLES;
  if (!Array.isArray(input.evidence) || input.evidence.length !== evidenceRoles.length) fail(code);
  for (let index = 0; index < evidenceRoles.length; index += 1) {
    const entry = input.evidence[index];
    exactKeys(entry, ['metadata', 'path', 'role', 'sha256'], code);
    if (entry.role !== evidenceRoles[index] || !path.isAbsolute(entry.path)) fail(code);
    requireSha(entry.sha256, code);
    exactKeys(entry.metadata, ['dev', 'gid', 'ino', 'mode', 'mtime_ns', 'nlink', 'size', 'uid'], code);
    const allowedMode = TERMINAL_ROOT_EVIDENCE_ROLES.has(entry.role)
      ? [0o444, 0o600] : [0o600];
    if (!allowedMode.includes(entry.metadata.mode) || entry.metadata.nlink !== 1
        || (entry.metadata.mode === 0o444
          && (entry.metadata.uid !== 0 || entry.metadata.gid !== 0))) fail(code);
  }
  if (!Array.isArray(input.scanReceipts) || input.scanReceipts.length !== TERMINAL_SCAN_IDS.length) fail(code);
  validateScanIds(input.scanReceipts.map(({ id }) => id));
  for (const receipt of input.scanReceipts) {
    exactKeys(receipt, ['id', 'metadata', 'path', 'sha256'], code);
    if (!path.isAbsolute(receipt.path)) fail(code);
    requireSha(receipt.sha256, code);
    exactKeys(receipt.metadata, ['dev', 'gid', 'ino', 'mode', 'mtime_ns', 'nlink', 'size', 'uid'], code);
    if (receipt.metadata.mode !== 0o600 || receipt.metadata.nlink !== 1) fail(code);
  }
  const expectedSettlementContracts = buildTerminalSettlementContracts({
    authoritySha: input.authoritySha,
    controllerGenerationId: input.generations.controller,
    terminalGenerationId: input.generations.terminal,
    runScansResultSha256: input.runScansResultSha256,
  });
  if (!Array.isArray(input.terminalSettlementContracts)
      || !canonicalJson(input.terminalSettlementContracts).equals(canonicalJson(expectedSettlementContracts))) fail(code);
  return {
    schema_version: 1,
    purpose: 'CI3_TERMINAL_ANCHOR_MANIFEST_V1',
    authority_sha: input.authoritySha,
    authority_tree: input.authorityTree,
    authority_manifest_sha256: input.authorityManifestSha256,
    components: structuredClone(input.components),
    generations: structuredClone(input.generations),
    bootstrap_claim_sha256: input.bootstrapClaimSha256,
    claim_result_chain_sha256: input.readChainSha256,
    remote_bundle_sha256: input.remoteBundleSha256,
    local_bundle_sha256: input.localBundleSha256,
    ssh_provenance_sha256: input.sshProvenanceSha256,
    simulator_gate_sha256: input.simulatorGateSha256,
    simulator_install_sha256: input.installReceiptSha256,
    evidence: structuredClone(input.evidence),
    scan_receipts: structuredClone(input.scanReceipts),
    terminal_settlement_contracts: structuredClone(input.terminalSettlementContracts),
    important_finding_ids: IMPORTANT_FINDINGS.map(({ id }) => id),
    writer_authority_path_sha256: input.writerAuthorityPathSha256,
    writer_source_sha256: input.writerSourceSha256,
    writer_binary_sha256: input.writerBinarySha256,
    writer_signature_sha256: input.writerSignatureSha256,
    anchor_relative_path: `${input.authoritySha}/${input.generations.terminal}/pre-anchor.json`,
    terminal_state: 'PRE_ANCHOR_PENDING_SETTLEMENT',
    created_at_utc: input.createdAtUtc,
    raw_values: false,
    secret_read: false,
    privilege_mode: 'MACOS_ROOT_SINGLE_ADMIN_PROMPT',
  };
}

export function buildTerminalSettlementContracts({
  authoritySha, controllerGenerationId, terminalGenerationId, runScansResultSha256,
} = {}) {
  const code = 'TERMINAL_SETTLEMENT_CONTRACT';
  requireSha(authoritySha, code, [40]);
  requireSha(runScansResultSha256, code);
  try {
    validateGenerationId(controllerGenerationId);
    validateGenerationId(terminalGenerationId);
  } catch { fail(code); }
  let predecessorContractSha256 = runScansResultSha256;
  return TERMINAL_SETTLEMENT_PHASES.map((phase) => {
    const contract = {
      schema_version: 1,
      purpose: 'CI3_TERMINAL_SETTLEMENT_CONTRACT_V1',
      phase,
      authority_sha: authoritySha,
      controller_generation_id: controllerGenerationId,
      terminal_generation_id: terminalGenerationId,
      predecessor_contract_sha256: predecessorContractSha256,
      effect_authorized: phase === 'INVOKE_WRITER' ? 'PRIVILEGED_WRITER_ON_FROZEN_MANIFEST' : 'REOPEN_ROOT_ANCHOR',
      raw_values: false,
    };
    predecessorContractSha256 = sha256(canonicalJson(contract));
    return contract;
  });
}

export function buildPreAnchorState({
  authoritySha, terminalGenerationId, manifestSha256, evidenceChainSha256,
} = {}) {
  const code = 'PRE_TERMINAL_ANCHOR';
  requireSha(authoritySha, code, [40]);
  requireSha(manifestSha256, code);
  requireSha(evidenceChainSha256, code);
  try { validateGenerationId(terminalGenerationId); } catch { fail(code); }
  return {
    schema_version: 1,
    purpose: 'CI3_PRE_TERMINAL_ANCHOR_V1',
    authority_sha: authoritySha,
    terminal_generation_id: terminalGenerationId,
    terminal_manifest_sha256: manifestSha256,
    evidence_chain_sha256: evidenceChainSha256,
    terminal_state: 'PENDING_VERIFICATION',
    raw_values: false,
    append_only: true,
    no_clobber: true,
  };
}

export function buildTerminalSettlementReceipt({
  authoritySha, generations, preAnchorSha256, invokeWriter,
  verifyAnchor, settlementAuthoritySha256, terminalSettlementContractsSha256,
  terminalPhaseGraphSha256, terminalFinalScanSha256,
} = {}) {
  const code = 'TERMINAL_SETTLEMENT';
  requireSha(authoritySha, code, [40]);
  requireSha(preAnchorSha256, code);
  requireSha(settlementAuthoritySha256, code);
  requireSha(terminalSettlementContractsSha256, code);
  requireSha(terminalPhaseGraphSha256, code);
  requireSha(terminalFinalScanSha256, code);
  exactKeys(generations, ['controller', 'remote', 'simulator', 'terminal'], code);
  try { for (const generationId of Object.values(generations)) validateGenerationId(generationId); } catch { fail(code); }
  const validateTriple = (triple) => {
    exactKeys(triple, ['claim_sha256', 'receipt_sha256', 'result_sha256'], code);
    for (const value of Object.values(triple)) requireSha(value, code);
    return structuredClone(triple);
  };
  const body = {
    schema_version: 1,
    purpose: 'CI3_TERMINAL_SETTLEMENT_V1',
    authority_sha: authoritySha,
    generations: structuredClone(generations),
    terminal_generation_id: generations.terminal,
    pre_anchor_sha256: preAnchorSha256,
    invoke_writer: validateTriple(invokeWriter),
    verify_anchor: validateTriple(verifyAnchor),
    settlement_authority_sha256: settlementAuthoritySha256,
    terminal_settlement_contracts_sha256: terminalSettlementContractsSha256,
    terminal_phase_graph_sha256: terminalPhaseGraphSha256,
    terminal_final_scan_sha256: terminalFinalScanSha256,
    terminal_state: 'TERMINAL_PASS',
    append_only: true,
    no_clobber: true,
    raw_values: false,
  };
  return { ...body, settlement_sha256: sha256(canonicalJson(body)) };
}

export function validateTerminalSettlementReceipt(receipt) {
  const code = 'TERMINAL_SETTLEMENT';
  exactKeys(receipt, [
    'append_only', 'authority_sha', 'invoke_writer', 'no_clobber',
    'generations', 'pre_anchor_sha256', 'purpose', 'raw_values', 'schema_version',
    'settlement_authority_sha256', 'settlement_sha256', 'terminal_generation_id',
    'terminal_final_scan_sha256', 'terminal_phase_graph_sha256', 'terminal_settlement_contracts_sha256',
    'terminal_state', 'verify_anchor',
  ], code);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_TERMINAL_SETTLEMENT_V1'
      || receipt.terminal_state !== 'TERMINAL_PASS' || receipt.append_only !== true
      || receipt.no_clobber !== true || receipt.raw_values !== false) fail(code);
  const { settlement_sha256: supplied, ...body } = receipt;
  const rebuilt = buildTerminalSettlementReceipt({
    authoritySha: receipt.authority_sha,
    generations: receipt.generations,
    preAnchorSha256: receipt.pre_anchor_sha256,
    invokeWriter: receipt.invoke_writer,
    verifyAnchor: receipt.verify_anchor,
    settlementAuthoritySha256: receipt.settlement_authority_sha256,
    terminalSettlementContractsSha256: receipt.terminal_settlement_contracts_sha256,
    terminalPhaseGraphSha256: receipt.terminal_phase_graph_sha256,
    terminalFinalScanSha256: receipt.terminal_final_scan_sha256,
  });
  if (receipt.terminal_generation_id !== receipt.generations.terminal
      || supplied !== rebuilt.settlement_sha256 || supplied !== sha256(canonicalJson(body))) fail(code);
  return true;
}

export function validateTerminalCompleteResult(receipt, { settlementBytes, finalScanBytes } = {}) {
  const code = 'TERMINAL_COMPLETE';
  exactKeys(receipt, [
    'authority_sha', 'generations', 'pre_anchor_sha256', 'purpose', 'raw_values',
    'schema_version', 'terminal_final_scan_sha256', 'terminal_generation_id',
    'terminal_settlement_sha256', 'terminal_state',
  ], code);
  requireSha(receipt.authority_sha, code, [40]);
  exactKeys(receipt.generations, ['controller', 'remote', 'simulator', 'terminal'], code);
  for (const generationId of Object.values(receipt.generations)) validateGenerationId(generationId);
  for (const value of [receipt.pre_anchor_sha256, receipt.terminal_final_scan_sha256, receipt.terminal_settlement_sha256]) requireSha(value, code);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_TERMINAL_COMPLETE_RESULT_V1'
      || receipt.terminal_generation_id !== receipt.generations.terminal
      || receipt.terminal_state !== 'COMPLETE' || receipt.raw_values !== false
      || !Buffer.isBuffer(settlementBytes) || !Buffer.isBuffer(finalScanBytes)
      || receipt.terminal_settlement_sha256 !== sha256(settlementBytes)
      || receipt.terminal_final_scan_sha256 !== sha256(finalScanBytes)) fail(code);
  return true;
}

export function validateTerminalCompleteFinalScan(receipt, completeBytes) {
  const code = 'TERMINAL_COMPLETE';
  exactKeys(receipt, [
    'authority_sha', 'input_byte_length', 'input_sha256', 'purpose', 'raw_values',
    'scan_results', 'schema_version', 'surface_roles', 'terminal_generation_id',
  ], code);
  requireSha(receipt.authority_sha, code, [40]);
  validateGenerationId(receipt.terminal_generation_id);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_TERMINAL_COMPLETE_FINAL_SCAN_V1'
      || receipt.raw_values !== false || !Buffer.isBuffer(completeBytes)
      || receipt.input_byte_length !== completeBytes.length || receipt.input_sha256 !== sha256(completeBytes)
      || !canonicalJson(receipt.surface_roles).equals(canonicalJson(['complete-result']))
      || !Array.isArray(receipt.scan_results) || receipt.scan_results.length !== TERMINAL_SCAN_IDS.length) fail(code);
  for (let index = 0; index < TERMINAL_SCAN_IDS.length; index += 1) {
    exactKeys(receipt.scan_results[index], ['id', 'match_count'], code);
    if (receipt.scan_results[index].id !== TERMINAL_SCAN_IDS[index]
        || receipt.scan_results[index].match_count !== 0) fail(code);
  }
  return true;
}

export function validateAuthorizedPhaseTargets({ contracts, observation } = {}) {
  const code = 'PHASE_TARGET_AUTHORITY';
  if (!Array.isArray(contracts) || !isPlainObject(observation) || !Array.isArray(observation.targets)) fail(code);
  const contract = contracts.find((candidate) => candidate?.phase === observation.phase);
  if (!contract || !Array.isArray(contract.targets) || contract.targets.length !== observation.targets.length) fail(code);
  for (let index = 0; index < contract.targets.length; index += 1) {
    const expected = contract.targets[index];
    const actual = observation.targets[index];
    exactKeys(expected, ['allowed_gids', 'allowed_uids', 'immutable', 'modes', 'path_sha256', 'role', 'state'], code);
    if (actual.role !== expected.role || actual.state !== expected.state
        || actual.path_sha256 !== expected.path_sha256
        || sha256(Buffer.from(actual.path ?? '')) !== expected.path_sha256) fail(code);
    if (actual.state === 'PRESENT') {
      if (!isPlainObject(actual.metadata) || actual.metadata.nlink !== 1
          || !expected.modes.includes(actual.metadata.mode & 0o777)
          || !expected.allowed_uids.includes(actual.metadata.uid)
          || !expected.allowed_gids.includes(actual.metadata.gid)) fail(code);
    }
  }
  return true;
}

export function validatePrivilegedWriterAuthorityReceipt(record, expected) {
  const code = 'STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY';
  exactKeys(record, [
    'anchor_path_sha256', 'attempt', 'authority_path_sha256', 'authority_sha', 'normal_executor_authorized',
    'privileged_claim_sha256', 'purpose', 'raw_values', 'retry', 'schema_version',
    'terminal_manifest_path_sha256',
    'terminal_generation_id', 'terminal_manifest_sha256', 'writer_binary_sha256',
    'writer_executable_gid', 'writer_executable_identity_sha256',
    'writer_executable_immutable_flag', 'writer_executable_mode',
    'writer_executable_path_sha256', 'writer_executable_uid',
    'writer_signature_sha256', 'writer_source_sha256',
  ], code);
  exactKeys(expected, [
    'anchorPathSha256', 'authorityPathSha256', 'authoritySha', 'privilegedClaimSha256',
    'terminalManifestPathSha256',
    'terminalGenerationId', 'terminalManifestSha256', 'writerBinarySha256',
    'writerExecutableIdentitySha256', 'writerExecutablePathSha256',
    'writerSignatureSha256', 'writerSourceSha256',
  ], code);
  if (record.schema_version !== 1
      || record.purpose !== 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1'
      || record.authority_sha !== expected.authoritySha
      || record.terminal_generation_id !== expected.terminalGenerationId
      || record.terminal_manifest_sha256 !== expected.terminalManifestSha256
      || record.writer_source_sha256 !== expected.writerSourceSha256
      || record.writer_binary_sha256 !== expected.writerBinarySha256
      || record.writer_signature_sha256 !== expected.writerSignatureSha256
      || record.privileged_claim_sha256 !== expected.privilegedClaimSha256
      || record.authority_path_sha256 !== expected.authorityPathSha256
      || record.anchor_path_sha256 !== expected.anchorPathSha256
      || record.terminal_manifest_path_sha256 !== expected.terminalManifestPathSha256
      || record.writer_executable_path_sha256 !== expected.writerExecutablePathSha256
      || record.writer_executable_identity_sha256 !== expected.writerExecutableIdentitySha256
      || record.writer_executable_uid !== 0 || record.writer_executable_gid !== 0
      || record.writer_executable_mode !== '0555'
      || record.writer_executable_immutable_flag !== 'UF_IMMUTABLE'
      || record.normal_executor_authorized !== false
      || record.attempt !== 1 || record.retry !== false || record.raw_values !== false) fail(code);
  return true;
}

export function buildPrivilegedPublisherClaim({
  authoritySha, terminalGenerationId, terminalManifestSha256,
  writerSourceSha256, writerBinarySha256, anchorPathSha256,
}) {
  requireSha(authoritySha, 'PRIVILEGED_AUTHORITY_PUBLISHER', [40]);
  validateGenerationId(terminalGenerationId);
  for (const value of [terminalManifestSha256, writerSourceSha256, writerBinarySha256, anchorPathSha256]) {
    requireSha(value, 'PRIVILEGED_AUTHORITY_PUBLISHER');
  }
  return {
    schema_version: 1,
    purpose: 'CI3_PRIVILEGED_TERMINAL_ANCHOR_CLAIM_V1',
    authority_sha: authoritySha,
    terminal_generation_id: terminalGenerationId,
    terminal_manifest_sha256: terminalManifestSha256,
    writer_source_sha256: writerSourceSha256,
    writer_binary_sha256: writerBinarySha256,
    anchor_path_sha256: anchorPathSha256,
    attempt: 1,
    retry: false,
    uid: 0,
    gid: 0,
    file_mode: '0444',
    immutable_flag: 'UF_IMMUTABLE',
    normal_executor_authorized: false,
  };
}

export function buildPrivilegedPublisherReceipt({
  authoritySha, terminalGenerationId, terminalManifestSha256,
  writerSourceSha256, writerBinarySha256, writerSignatureSha256,
  privilegedClaimSha256, authorityPathSha256, anchorPathSha256,
  terminalManifestPathSha256, writerExecutablePathSha256,
  writerExecutableIdentitySha256,
}) {
  const receipt = {
    schema_version: 1,
    purpose: 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1',
    authority_sha: authoritySha,
    terminal_generation_id: terminalGenerationId,
    terminal_manifest_sha256: terminalManifestSha256,
    writer_source_sha256: writerSourceSha256,
    writer_binary_sha256: writerBinarySha256,
    writer_signature_sha256: writerSignatureSha256,
    privileged_claim_sha256: privilegedClaimSha256,
    authority_path_sha256: authorityPathSha256,
    anchor_path_sha256: anchorPathSha256,
    terminal_manifest_path_sha256: terminalManifestPathSha256,
    writer_executable_path_sha256: writerExecutablePathSha256,
    writer_executable_identity_sha256: writerExecutableIdentitySha256,
    writer_executable_uid: 0,
    writer_executable_gid: 0,
    writer_executable_mode: '0555',
    writer_executable_immutable_flag: 'UF_IMMUTABLE',
    normal_executor_authorized: false,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  validatePrivilegedWriterAuthorityReceipt(receipt, {
    authoritySha, terminalGenerationId, terminalManifestSha256,
    writerSourceSha256, writerBinarySha256, writerSignatureSha256,
    privilegedClaimSha256, authorityPathSha256, anchorPathSha256,
    terminalManifestPathSha256, writerExecutablePathSha256,
    writerExecutableIdentitySha256,
  });
  return receipt;
}

export function privilegedWriterExecutablePath(authoritySha, terminalGenerationId) {
  requireSha(authoritySha, 'STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY', [40]);
  validateGenerationId(terminalGenerationId);
  return path.join(
    '/Library/Application Support/Agentempp/ci3-terminal-authority',
    authoritySha, terminalGenerationId, 'writer', 'ci3-terminal-anchor-writer',
  );
}

export function selectPrivilegedWriterInvocation({ authorityReceipt, expected }) {
  validatePrivilegedWriterAuthorityReceipt(authorityReceipt, expected);
  const executablePath = privilegedWriterExecutablePath(expected.authoritySha, expected.terminalGenerationId);
  if (sha256(Buffer.from(executablePath)) !== authorityReceipt.writer_executable_path_sha256) {
    fail('STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY');
  }
  return Object.freeze({
    executablePath,
    executableSha256: authorityReceipt.writer_binary_sha256,
    executableIdentitySha256: authorityReceipt.writer_executable_identity_sha256,
    authorityReceiptSha256: sha256(canonicalJson(authorityReceipt)),
  });
}

export function validateExistingState({ state, originalClaim, expected }) {
  if (!originalClaim) fail('REJECT_UNCLAIMED_EXISTING_STATE');
  if (!['bundle', 'capture', 'result', 'install', 'anchor'].includes(state) || !expected) fail('EXISTING_STATE');
  if (!canonicalJson(originalClaim).equals(canonicalJson({
    sha256: expected.claim_sha256,
    generations: expected.generations,
    components: expected.components,
    authority_sha: expected.authority_sha,
  }))) fail('EXISTING_STATE');
  return true;
}

export function validateVpsOperationAuthorityPass(receipt, expected = {}) {
  const code = 'VPS_OPERATION_AUTHORITY_PASS';
  exactKeys(receipt, [
    'attempt', 'authority_manifest_sha256', 'authority_parent', 'authority_sha',
    'authority_subject_sha256', 'authority_tree', 'collector_contracts_sha256',
    'controller_generation_id', 'node_candidate_sha256',
    'operation_authority_sha256', 'publisher_input_manifest_sha256', 'purpose',
    'raw_values', 'remote_generation_id', 'retry', 'schema_version',
    'source_generation_id', 'transfer_payload_sha256',
    'issuer_authority_sha256', 'issuer_key_sha256', 'signature_base64',
    'signed_payload_sha256',
  ], code);
  if (receipt.schema_version !== 1
      || receipt.purpose !== 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1'
      || receipt.authority_parent !== AUTHORITY_PARENT
      || receipt.attempt !== 1 || receipt.retry !== false || receipt.raw_values !== false
      || !/^src-[a-f0-9]{64}$/.test(receipt.source_generation_id ?? '')) fail(code);
  requireSha(receipt.authority_sha, code, [40]);
  requireSha(receipt.authority_tree, code, [40]);
  try {
    validateGenerationId(receipt.remote_generation_id);
    validateGenerationId(receipt.controller_generation_id);
  } catch { fail(code); }
  for (const field of [
    'authority_manifest_sha256', 'authority_subject_sha256', 'collector_contracts_sha256',
    'issuer_authority_sha256', 'issuer_key_sha256', 'signed_payload_sha256',
    'node_candidate_sha256', 'operation_authority_sha256',
    'publisher_input_manifest_sha256', 'transfer_payload_sha256',
  ]) requireSha(receipt[field], code);
  if (typeof receipt.signature_base64 !== 'string'
      || Buffer.from(receipt.signature_base64, 'base64').toString('base64') !== receipt.signature_base64
      || Buffer.from(receipt.signature_base64, 'base64').length !== 64) fail(code);
  const bindings = {
    authoritySha: 'authority_sha', authorityTree: 'authority_tree',
    authoritySubjectSha256: 'authority_subject_sha256',
    authorityManifestSha256: 'authority_manifest_sha256',
    operationAuthoritySha256: 'operation_authority_sha256',
    nodeCandidateSha256: 'node_candidate_sha256',
    collectorContractsSha256: 'collector_contracts_sha256',
    publisherInputManifestSha256: 'publisher_input_manifest_sha256',
    remoteGenerationId: 'remote_generation_id',
    controllerGenerationId: 'controller_generation_id',
    transferPayloadSha256: 'transfer_payload_sha256',
  };
  for (const [inputField, receiptField] of Object.entries(bindings)) {
    if (expected[inputField] === undefined || expected[inputField] !== receipt[receiptField]) fail(code);
  }
  return true;
}

export function vpsPassSigningPayload(receipt) {
  const code = 'VPS_OPERATION_AUTHORITY_SIGNATURE';
  if (!isPlainObject(receipt)) fail(code);
  const payload = structuredClone(receipt);
  delete payload.signed_payload_sha256;
  delete payload.signature_base64;
  if (payload.purpose !== 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1') fail(code);
  requireSha(payload.issuer_authority_sha256, code);
  requireSha(payload.issuer_key_sha256, code);
  return canonicalJson(payload);
}

export function validateVpsExternalIssuerAuthority(issuer) {
  const code = 'VPS_EXTERNAL_ISSUER_AUTHORITY';
  exactKeys(issuer, [
    'allowed_pass_purpose', 'authority_sha', 'issuer_generation_id',
    'issuer_identity_sha256', 'normal_executor_authorized', 'public_key_algorithm',
    'public_key_raw_base64', 'public_key_sha256', 'purpose', 'raw_values',
    'schema_version',
  ], code);
  if (issuer.schema_version !== 1
      || issuer.purpose !== 'CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1'
      || issuer.allowed_pass_purpose !== 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1'
      || issuer.public_key_algorithm !== 'Ed25519'
      || issuer.normal_executor_authorized !== false || issuer.raw_values !== false
      || !/^issuer-[a-f0-9]{64}$/.test(issuer.issuer_generation_id ?? '')) fail(code);
  requireSha(issuer.authority_sha, code, [40]);
  requireSha(issuer.issuer_identity_sha256, code);
  requireSha(issuer.public_key_sha256, code);
  if (typeof issuer.public_key_raw_base64 !== 'string') fail(code);
  const publicKey = Buffer.from(issuer.public_key_raw_base64, 'base64');
  if (publicKey.length !== 32 || publicKey.toString('base64') !== issuer.public_key_raw_base64
      || sha256(publicKey) !== issuer.public_key_sha256) fail(code);
  return publicKey;
}

export function verifySignedVpsOperationAuthorityPass(receipt, issuer, expected = null) {
  if (!issuer) fail('STOP_PRE_AUTHORITY');
  const publicKey = validateVpsExternalIssuerAuthority(issuer);
  const issuerSha256 = sha256(canonicalJson(issuer));
  if (receipt?.issuer_authority_sha256 !== issuerSha256
      || receipt?.issuer_key_sha256 !== issuer.public_key_sha256
      || receipt?.authority_sha !== issuer.authority_sha) fail('VPS_OPERATION_AUTHORITY_SIGNATURE');
  const payload = vpsPassSigningPayload(receipt);
  if (receipt.signed_payload_sha256 !== sha256(payload)) fail('VPS_OPERATION_AUTHORITY_SIGNATURE');
  let key;
  try {
    key = createPublicKey({
      key: { kty: 'OKP', crv: 'Ed25519', x: publicKey.toString('base64url') },
      format: 'jwk',
    });
  } catch { fail('VPS_OPERATION_AUTHORITY_SIGNATURE'); }
  if (!verifySignature(null, payload, key, Buffer.from(receipt.signature_base64, 'base64'))) {
    fail('VPS_OPERATION_AUTHORITY_SIGNATURE');
  }
  validateVpsOperationAuthorityPass(receipt, expected ?? {
    authoritySha: receipt.authority_sha,
    authorityTree: receipt.authority_tree,
    authoritySubjectSha256: receipt.authority_subject_sha256,
    authorityManifestSha256: receipt.authority_manifest_sha256,
    operationAuthoritySha256: receipt.operation_authority_sha256,
    nodeCandidateSha256: receipt.node_candidate_sha256,
    collectorContractsSha256: receipt.collector_contracts_sha256,
    publisherInputManifestSha256: receipt.publisher_input_manifest_sha256,
    remoteGenerationId: receipt.remote_generation_id,
    controllerGenerationId: receipt.controller_generation_id,
    transferPayloadSha256: receipt.transfer_payload_sha256,
  });
  return true;
}

export function signVpsOperationAuthorityPass({ unsigned, issuer, privateKey } = {}) {
  validateVpsExternalIssuerAuthority(issuer);
  if (!isPlainObject(unsigned) || !privateKey
      || unsigned.issuer_authority_sha256 !== sha256(canonicalJson(issuer))
      || unsigned.issuer_key_sha256 !== issuer.public_key_sha256) fail('VPS_OPERATION_AUTHORITY_SIGNATURE');
  const pass = structuredClone(unsigned);
  delete pass.signed_payload_sha256;
  delete pass.signature_base64;
  const payload = canonicalJson(pass);
  pass.signed_payload_sha256 = sha256(payload);
  pass.signature_base64 = signSignature(null, payload, privateKey).toString('base64');
  verifySignedVpsOperationAuthorityPass(pass, issuer);
  return pass;
}

async function readVpsRootImmutableFile(filePath, mode, code, { returnObservation = false } = {}) {
  if (typeof process.getuid !== 'function' || process.getuid() !== 0 || process.geteuid() !== 0) fail('STOP_PRE_AUTHORITY');
  if (!path.isAbsolute(filePath ?? '')
      || (!filePath.startsWith('/var/lib/agentempp/') && !filePath.startsWith('/etc/agentempp/'))) fail(code);
  const observed = await descriptorRelativeFileTransaction({
    root: '/', relativePath: filePath.slice(1), operation: 'read', expectedMode: mode,
    expectedUid: 0, expectedGid: 0, allowedDirectoryModes: [0o755, 0o700, 0o555],
    requireImmutable: true,
  }).catch((error) => {
    if (error?.code === 'STOP_PRE_AUTHORITY') throw error;
    fail(code);
  });
  if (observed.immutable !== true) fail(code);
  return returnObservation ? observed : observed.bytes;
}

export async function createVpsOperationAuthorityPassPublisher({ launchAttestation, bootstrapBoundary = null, io = null } = {}) {
  validateLaunchAttestation(launchAttestation);
  const code = 'VPS_PUBLISHER0';
  if (io === null && (!isPlainObject(bootstrapBoundary)
      || bootstrapBoundary.authority_sha !== launchAttestation.authority_sha)) fail('VPS_PUBLISHER0_BOOTSTRAP');
  const authorityRoot = path.join('/var/lib/agentempp/ci3-vps-authority', launchAttestation.authority_sha);
  const issuerPath = path.join(authorityRoot, 'issuer-authority.receipt.json');
  const requestPath = path.join(authorityRoot, 'vps-operation-authority.unsigned.json');
  const privateKeyPath = path.join(authorityRoot, 'issuer-signing-key.pkcs8');
  const passPath = path.join(authorityRoot, 'vps-operation-authority.pass.json');
  const operationalIO = io ?? {
    readIssuer: () => readVpsRootImmutableFile(issuerPath, 0o444, code),
    readUnsignedRequest: () => readVpsRootImmutableFile(requestPath, 0o444, code),
    readPrivateKey: () => readVpsRootImmutableFile(privateKeyPath, 0o400, code),
    publishNoClobber: async (bytes) => {
      const published = await descriptorRelativeFileTransaction({
        root: '/', relativePath: passPath.slice(1), operation: 'create-exclusive', bytes,
        expectedMode: 0o444, expectedUid: 0, expectedGid: 0,
        allowedDirectoryModes: [0o755, 0o700, 0o555],
        makeImmutable: true, requireImmutable: true,
      }).catch((error) => {
        if (error?.code === 'DESCRIPTOR_NO_CLOBBER') fail('VPS_PUBLISHER0_NO_CLOBBER');
        throw error;
      });
      if (!published.bytes.equals(bytes) || published.immutable !== true) fail(code);
      return 'CREATED';
    },
  };
  for (const method of ['readIssuer', 'readUnsignedRequest', 'readPrivateKey', 'publishNoClobber']) {
    if (typeof operationalIO[method] !== 'function') fail(code);
  }
  return {
    publishVpsOperationAuthorityPass: async () => {
      const [issuerBytes, requestBytes, privateKeyBytes] = await Promise.all([
        operationalIO.readIssuer(), operationalIO.readUnsignedRequest(), operationalIO.readPrivateKey(),
      ]);
      let issuer;
      let unsigned;
      let privateKey;
      try {
        issuer = JSON.parse(issuerBytes.toString('utf8'));
        unsigned = JSON.parse(requestBytes.toString('utf8'));
        privateKey = createPrivateKey({ key: privateKeyBytes, format: 'der', type: 'pkcs8' });
      } catch { fail(code); }
      if (bootstrapBoundary !== null && sha256(issuerBytes) !== bootstrapBoundary.issuer_receipt_sha256) fail(code);
      if (issuer.authority_sha !== launchAttestation.authority_sha
          || unsigned.authority_sha !== launchAttestation.authority_sha
          || unsigned.authority_parent !== launchAttestation.authority_parent
          || unsigned.authority_tree !== launchAttestation.authority_tree
          || unsigned.authority_subject_sha256 !== launchAttestation.authority_subject_sha256
          || unsigned.authority_manifest_sha256 !== launchAttestation.authority_manifest_sha256) fail(code);
      const signed = signVpsOperationAuthorityPass({ unsigned, issuer, privateKey });
      const bytes = canonicalJson(signed);
      const status = await operationalIO.publishNoClobber(bytes);
      if (status !== 'CREATED') fail(code);
      return { status, pass_sha256: sha256(bytes), raw_values: false };
    },
  };
}

export function classifyRecovery({ claim, capture, result, generationDrift = false, provenanceDrift = false }) {
  if (!claim && (capture || result)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
  if (!claim && !capture && !result) return { state: 'ABSENT', refetch: false };
  if (generationDrift || provenanceDrift || (!capture && result)) return { state: 'DIVERGENT', refetch: false };
  if (claim && !capture && !result) return { state: 'CLAIM_CONSUMED_NO_RESULT', refetch: false };
  if (claim && capture && !result) return { state: 'CAPTURE_PENDING_RESULT_LOCAL_ONLY', refetch: false };
  if (claim && capture && result) return { state: 'LOCAL_RECOVERY', refetch: false };
  return { state: 'DIVERGENT', refetch: false };
}

const DURABLE_PHASES = Object.freeze([
  'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
  'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
  'INVOKE_WRITER', 'VERIFY_ANCHOR',
]);

export function buildPhaseClaim({ phase, authoritySha, controllerGenerationId, predecessorResultSha256, contractSha256 }) {
  const code = 'PHASE_CLAIM';
  if (!DURABLE_PHASES.includes(phase)) fail(code);
  requireSha(authoritySha, code, [40]);
  validateGenerationId(controllerGenerationId);
  for (const value of [predecessorResultSha256, contractSha256]) requireSha(value, code);
  return {
    schema_version: 1,
    purpose: 'CI3_MAC_PHASE_CLAIM_V1',
    phase,
    authority_sha: authoritySha,
    controller_generation_id: controllerGenerationId,
    predecessor_result_sha256: predecessorResultSha256,
    contract_sha256: contractSha256,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
}

export function buildPhaseResult({ phase, claimSha256, receiptSha256, physicalObservationSha256 }) {
  const code = 'PHASE_RESULT';
  if (!DURABLE_PHASES.includes(phase)) fail(code);
  for (const value of [claimSha256, receiptSha256, physicalObservationSha256]) requireSha(value, code);
  return {
    schema_version: 1,
    purpose: 'CI3_MAC_PHASE_RESULT_V1',
    phase,
    claim_sha256: claimSha256,
    receipt_sha256: receiptSha256,
    physical_observation_sha256: physicalObservationSha256,
    terminal_state: 'PHASE_SETTLED',
    raw_values: false,
  };
}

export function buildPhysicalObservationSha256({ bytes, metadata } = {}) {
  const code = 'PHASE_PHYSICAL_OBSERVATION';
  if (!Buffer.isBuffer(bytes) || !isPlainObject(metadata)) fail(code);
  exactKeys(metadata, ['dev', 'gid', 'ino', 'mode', 'mtime_ns', 'nlink', 'size', 'uid'], code);
  if (![metadata.dev, metadata.ino, metadata.mtime_ns].every((value) => /^[0-9]+$/.test(String(value)))
      || !Number.isInteger(metadata.uid) || !Number.isInteger(metadata.gid)
      || !Number.isInteger(metadata.mode) || !Number.isInteger(metadata.nlink)
      || !Number.isInteger(metadata.size) || metadata.size !== bytes.length || metadata.nlink !== 1) fail(code);
  return sha256(Buffer.from([
    `bytes=${sha256(bytes)}`, `uid=${metadata.uid}`, `gid=${metadata.gid}`,
    `mode=${metadata.mode & 0o777}`, `nlink=${metadata.nlink}`, `size=${metadata.size}`,
    `mtime=${String(metadata.mtime_ns)}`, `dev=${String(metadata.dev)}`, `ino=${String(metadata.ino)}`,
  ].join(';')));
}

export async function observePhysicalEffect({ phase, targets } = {}) {
  const code = 'PHASE_PHYSICAL_OBSERVATION';
  if (!DURABLE_PHASES.includes(phase) || !Array.isArray(targets) || targets.length === 0) fail(code);
  const roles = new Set();
  const observedTargets = [];
  for (const target of targets) {
    if (!isPlainObject(target) || typeof target.role !== 'string'
        || !/^[a-z0-9-]+$/.test(target.role) || roles.has(target.role)
        || !path.isAbsolute(target.path ?? '') || !['PRESENT', 'ABSENT'].includes(target.state)) fail(code);
    roles.add(target.role);
    const pathSha256 = sha256(Buffer.from(target.path));
    if (target.state === 'ABSENT') {
      const existing = await lstat(target.path).catch((error) => {
        if (error?.code === 'ENOENT') return null;
        throw error;
      });
      if (existing !== null) fail(code);
      observedTargets.push({
        role: target.role, state: 'ABSENT', path: target.path, path_sha256: pathSha256,
        sha256: null, identity_sha256: null, metadata: null,
      });
      continue;
    }
    requireSha(target.expectedSha256, code);
    const opened = await readBoundLocalFile(target.path, {
      code,
      expectedSha256: target.expectedSha256,
      modes: target.modes ?? [0o600],
      allowedUids: target.allowedUids ?? [process.getuid()],
      allowedGids: target.allowedGids ?? [process.getgid()],
    });
    if (target.requireImmutable === true) {
      const flags = runFixedCommand('/usr/bin/stat', ['-f', '%Sf', target.path]);
      if (flags.stderr.length !== 0 || !flags.stdout.toString('utf8').trim().split(',').includes('uchg')) fail(code);
    }
    observedTargets.push({
      role: target.role,
      state: 'PRESENT',
      path: target.path,
      path_sha256: pathSha256,
      sha256: sha256(opened.bytes),
      identity_sha256: physicalIdentitySha256(opened.metadata),
      metadata: opened.metadata,
    });
  }
  const body = {
    schema_version: 1,
    purpose: 'CI3_MAC_PHASE_EFFECT_OBSERVATION_V1',
    phase,
    targets: observedTargets,
    raw_values: false,
  };
  return { ...body, observation_sha256: sha256(canonicalJson(body)) };
}

export function validatePhysicalEffectObservation(observation, phase) {
  const code = 'PHASE_PHYSICAL_OBSERVATION';
  exactKeys(observation, [
    'observation_sha256', 'phase', 'purpose', 'raw_values', 'schema_version', 'targets',
  ], code);
  if (observation.schema_version !== 1
      || observation.purpose !== 'CI3_MAC_PHASE_EFFECT_OBSERVATION_V1'
      || observation.phase !== phase || observation.raw_values !== false
      || !Array.isArray(observation.targets) || observation.targets.length === 0) fail(code);
  const seen = new Set();
  for (const target of observation.targets) {
    exactKeys(target, ['identity_sha256', 'metadata', 'path', 'path_sha256', 'role', 'sha256', 'state'], code);
    if (typeof target.role !== 'string' || !/^[a-z0-9-]+$/.test(target.role)
        || seen.has(target.role) || !['PRESENT', 'ABSENT'].includes(target.state)
        || !path.isAbsolute(target.path ?? '')
        || sha256(Buffer.from(target.path)) !== target.path_sha256) fail(code);
    seen.add(target.role);
    requireSha(target.path_sha256, code);
    if (target.state === 'PRESENT') {
      requireSha(target.sha256, code);
      requireSha(target.identity_sha256, code);
      exactKeys(target.metadata, ['dev', 'gid', 'ino', 'mode', 'mtime_ns', 'nlink', 'size', 'uid'], code);
      if (physicalIdentitySha256(target.metadata) !== target.identity_sha256) fail(code);
    } else if (target.sha256 !== null || target.identity_sha256 !== null || target.metadata !== null) fail(code);
  }
  const { observation_sha256: supplied, ...body } = observation;
  if (supplied !== sha256(canonicalJson(body))) fail(code);
  return true;
}

export async function recoverSettledPhase({ persistedObservation, reobserve } = {}) {
  if (typeof reobserve !== 'function') fail('CLAIM_CONSUMED_NO_RESULT');
  let settled;
  try { settled = await reobserve(); } catch { fail('PHASE_RECOVERY_DIVERGENCE'); }
  if (persistedObservation !== undefined) {
    if (!settled || !canonicalJson(settled).equals(canonicalJson(persistedObservation))) fail('PHASE_RECOVERY_DIVERGENCE');
    return settled;
  }
  if (!settled || settled.result === undefined || settled.result === null) fail('CLAIM_CONSUMED_NO_RESULT');
  requireSha(settled.receiptSha256, 'PHASE_RECOVERY_DIVERGENCE');
  requireSha(settled.physicalObservationSha256, 'PHASE_RECOVERY_DIVERGENCE');
  return settled;
}

export async function settleSimulatorPhaseObservation({ priorReceipt, effect, reobserve } = {}) {
  if (priorReceipt) {
    if (!isPlainObject(priorReceipt.observation) || typeof reobserve !== 'function') fail('SIMULATOR_GATE');
    let observation;
    try { observation = await reobserve(); } catch { fail('SIMULATOR_GATE'); }
    if (!isPlainObject(observation)
        || !canonicalJson(observation).equals(canonicalJson(priorReceipt.observation))) fail('SIMULATOR_GATE');
    return { observation, recovered: true };
  }
  if (typeof effect !== 'function') fail('SIMULATOR_GATE');
  const observation = await effect();
  if (!isPlainObject(observation)) fail('SIMULATOR_GATE');
  return { observation, recovered: false };
}

export async function assertSimulatorProbeTargetsAbsent(paths) {
  if (!Array.isArray(paths) || paths.length !== 3 || new Set(paths).size !== 3
      || paths.some((candidate) => !path.isAbsolute(candidate))) fail('SIMULATOR_GATE');
  for (const candidate of paths) {
    const observed = await lstat(candidate).catch((error) => {
      if (error?.code === 'ENOENT') return null;
      throw error;
    });
    if (observed !== null) fail('REJECT_UNCLAIMED_EXISTING_STATE');
  }
  return true;
}

async function ensurePrivateDirectory(directoryPath) {
  try {
    await mkdir(directoryPath, { recursive: false, mode: 0o700 });
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
  }
  const observed = await lstat(directoryPath);
  if (!observed.isDirectory() || observed.isSymbolicLink()
      || (observed.mode & 0o777) !== 0o700
      || observed.uid !== process.getuid() || observed.gid !== process.getgid()) fail('JOURNAL_DIRECTORY');
}

async function readPrivateJson(filePath, missingIsNull = false) {
  let observed;
  try {
    observed = await lstat(filePath);
  } catch (error) {
    if (missingIsNull && error?.code === 'ENOENT') return null;
    throw error;
  }
  if (!observed.isFile() || observed.isSymbolicLink() || observed.nlink !== 1
      || (observed.mode & 0o777) !== 0o600
      || observed.uid !== process.getuid() || observed.gid !== process.getgid()) fail('JOURNAL_PHYSICAL');
  const handle = await open(filePath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
  try {
    const before = await handle.stat({ bigint: true });
    const bytes = await handle.readFile();
    const after = await handle.stat({ bigint: true });
    const finalPath = await lstat(filePath, { bigint: true });
    if (!sameBigIntStat(before, after) || !sameBigIntStat(after, finalPath)) fail('JOURNAL_PHYSICAL');
    return JSON.parse(bytes.toString('utf8'));
  } catch (error) {
    if (error instanceof ControllerError) throw error;
    fail('JOURNAL_JSON');
  } finally {
    await handle.close();
  }
}

async function fsyncDirectory(directoryPath) {
  const handle = await open(directoryPath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
  try { await handle.sync(); } finally { await handle.close(); }
}

export async function promoteDirectoryNoReplace({ stagingRoot, finalRoot, beforeRename, exclusiveRename, lstatFn = lstat } = {}) {
  const code = 'LOCAL_PUBLICATION_RACE';
  const names = ['mobile-staging-config.json', 'synthetic-patient.credentials.json', 'local-bridge.receipt.json'];
  if (!path.isAbsolute(stagingRoot ?? '') || !path.isAbsolute(finalRoot ?? '')
      || path.dirname(stagingRoot) !== path.dirname(finalRoot) || stagingRoot === finalRoot
      || typeof exclusiveRename !== 'function' || typeof lstatFn !== 'function') fail(code);
  const expectedUid = BigInt(process.getuid());
  const expectedGid = BigInt(process.getgid());
  const stagingBefore = await lstatFn(stagingRoot, { bigint: true });
  if (!stagingBefore.isDirectory() || stagingBefore.isSymbolicLink()
      || (stagingBefore.mode & 0o777n) !== 0o700n || stagingBefore.nlink < 1n
      || stagingBefore.uid !== expectedUid || stagingBefore.gid !== expectedGid) fail(code);
  const parent = await lstatFn(path.dirname(stagingRoot), { bigint: true });
  if (!parent.isDirectory() || parent.isSymbolicLink() || parent.dev !== stagingBefore.dev
      || parent.uid !== expectedUid || parent.gid !== expectedGid) fail(code);
  const stagedEntries = (await readdir(stagingRoot)).sort();
  if (JSON.stringify(stagedEntries) !== JSON.stringify([...names].sort())) fail(code);
  const stagedHashes = new Map();
  for (const name of names) {
    const staged = await readBoundLocalFile(path.join(stagingRoot, name), { code, modes: [0o600] });
    stagedHashes.set(name, sha256(staged.bytes));
  }
  const finalBefore = await lstatFn(finalRoot, { bigint: true }).catch((error) => {
    if (error?.code === 'ENOENT') return null;
    throw error;
  });
  if (finalBefore) fail(code);
  await beforeRename?.();
  await exclusiveRename({ source: stagingRoot, destination: finalRoot }).catch(() => fail(code));
  const finalAfter = await lstatFn(finalRoot, { bigint: true });
  if (!finalAfter.isDirectory() || finalAfter.isSymbolicLink()
      || finalAfter.dev !== stagingBefore.dev || finalAfter.ino !== stagingBefore.ino
      || (finalAfter.mode & 0o777n) !== 0o700n
      || finalAfter.uid !== expectedUid || finalAfter.gid !== expectedGid) fail(code);
  await lstatFn(stagingRoot, { bigint: true }).then(
    () => fail(code), (error) => { if (error?.code !== 'ENOENT') throw error; },
  );
  const finalEntries = (await readdir(finalRoot)).sort();
  if (JSON.stringify(finalEntries) !== JSON.stringify([...names].sort())) fail(code);
  for (const name of names) {
    const published = await readBoundLocalFile(path.join(finalRoot, name), { code, modes: [0o600] });
    if (sha256(published.bytes) !== stagedHashes.get(name)) fail(code);
  }
  await fsyncDirectory(finalRoot);
  await fsyncDirectory(path.dirname(finalRoot));
  return { status: 'CREATED', finalRoot, commit_marker: 'local-bridge.receipt.json' };
}

async function writeOnceJson(filePath, value) {
  const bytes = canonicalJson(value);
  let handle;
  try {
    handle = await open(filePath, 'wx', 0o600);
    await handle.writeFile(bytes);
    await handle.sync();
    await handle.close();
    handle = null;
    await fsyncDirectory(path.dirname(filePath));
    return sha256(bytes);
  } catch (error) {
    if (handle) await handle.close().catch(() => {});
    if (error?.code !== 'EEXIST') throw error;
    const existing = await readPrivateJson(filePath);
    if (!canonicalJson(existing).equals(bytes)) fail('JOURNAL_DIVERGENT_EXISTING');
    return sha256(bytes);
  }
}

async function writeOnceBytes(filePath, bytes) {
  let handle;
  try {
    handle = await open(filePath, 'wx', 0o600);
    await handle.writeFile(bytes);
    await handle.sync();
    await handle.close();
    handle = null;
    await fsyncDirectory(path.dirname(filePath));
  } catch (error) {
    if (handle) await handle.close().catch(() => {});
    if (error?.code !== 'EEXIST') throw error;
    const existing = await readFile(filePath);
    if (!existing.equals(bytes)) fail('CAPTURE_DIVERGENT_EXISTING');
  }
  return sha256(bytes);
}

async function collectJournalFiles(directory, root, output) {
  const entries = await readdir(directory, { withFileTypes: true });
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const candidate = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) fail('TERMINAL_JOURNAL_FRAME');
    if (entry.isDirectory()) await collectJournalFiles(candidate, root, output);
    else if (entry.isFile()) output.push(path.relative(root, candidate));
    else fail('TERMINAL_JOURNAL_FRAME');
  }
}

export async function materializeActualJournalFrame({ generationRoot, destinationPath, context } = {}) {
  const code = 'TERMINAL_JOURNAL_FRAME';
  validateTerminalPassContext(context, code);
  if (!path.isAbsolute(generationRoot ?? '') || !path.isAbsolute(destinationPath ?? '')
      || path.basename(generationRoot) !== context.generations.controller
      || path.basename(path.dirname(generationRoot)) !== context.authority.commit) fail(code);
  const relativePaths = [];
  await collectJournalFiles(generationRoot, generationRoot, relativePaths);
  const objects = [];
  const frames = [];
  for (const relativePath of relativePaths.sort()) {
    if (!/^[A-Za-z0-9._/-]+$/.test(relativePath) || relativePath.includes('..')) fail(code);
    const observed = await readBoundLocalFile(path.join(generationRoot, relativePath), {
      code, modes: [0o600],
    });
    for (const scanId of TERMINAL_SCAN_IDS) {
      if (scanTerminalSurface(scanId, observed.bytes).total !== 0) fail(code);
    }
    const relativeBytes = Buffer.from(relativePath);
    frames.push(Buffer.from(`${relativeBytes.length}:`), relativeBytes, Buffer.from(`\n${observed.bytes.length}:`), observed.bytes, Buffer.from('\n'));
    objects.push({
      relative_path: relativePath, path_sha256: sha256(relativeBytes),
      sha256: sha256(observed.bytes), byte_length: observed.bytes.length,
      identity_sha256: physicalIdentitySha256(observed.metadata),
    });
  }
  const frame = Buffer.concat(frames);
  for (const scanId of TERMINAL_SCAN_IDS) if (scanTerminalSurface(scanId, frame).total !== 0) fail(code);
  const receipt = {
    schema_version: 1, purpose: 'CI3_OPERATIONAL_DURABLE_JOURNAL_FRAME_V1',
    authority_sha: context.authority.commit, generations: structuredClone(context.generations),
    object_count: objects.length, objects, frame_base64: frame.toString('base64'),
    frame_sha256: sha256(frame), frame_byte_length: frame.length,
    raw_scanned_before_encoding: true, raw_values: false,
  };
  await writeOnceBytes(destinationPath, canonicalJson(receipt));
  const readback = await readBoundLocalFile(destinationPath, {
    code, expectedSha256: sha256(canonicalJson(receipt)), modes: [0o600],
  });
  return { receipt, frame, identity_sha256: readback.identity_sha256 };
}

export async function createVersionedJournal({
  root, authoritySha, controllerGenerationId, terminalAuthority = null,
}) {
  if (!path.isAbsolute(root ?? '') || !isSha(authoritySha, [40])) fail('JOURNAL_AUTHORITY');
  validateGenerationId(controllerGenerationId);
  await ensurePrivateDirectory(root);
  const authorityRoot = path.join(root, authoritySha);
  await ensurePrivateDirectory(authorityRoot);
  const generationRoot = path.join(authorityRoot, controllerGenerationId);
  await ensurePrivateDirectory(generationRoot);
  const eventsRoot = path.join(generationRoot, 'events');
  const claimsRoot = path.join(generationRoot, 'claims');
  const resultsRoot = path.join(generationRoot, 'results');
  const receiptsRoot = path.join(generationRoot, 'physical-receipts');
  for (const directoryPath of [eventsRoot, claimsRoot, resultsRoot, receiptsRoot]) await ensurePrivateDirectory(directoryPath);
  const eventPath = (event) => {
    if (!/^[A-Z_]+$/.test(event ?? '')) fail('JOURNAL_EVENT');
    return path.join(eventsRoot, `${event}.json`);
  };
  const claimName = (claim) => {
    if (claim?.purpose === 'CI3_MAC_BRIDGE_BOOTSTRAP_CLAIM_V1') return 'bootstrap';
    if (claim?.purpose === 'CI3_MAC_BRIDGE_READ_CLAIM_V1' && ['receipt', 'config', 'credential'].includes(claim.kind)) return claim.kind;
    fail('JOURNAL_CLAIM');
  };
  const resultName = (result) => {
    if (result?.purpose === 'CI3_MAC_BRIDGE_READ_RESULT_V1' && ['receipt', 'config', 'credential'].includes(result.kind)) return result.kind;
    fail('JOURNAL_RESULT');
  };
  if (terminalAuthority !== null && (!isPlainObject(terminalAuthority)
      || !isPlainObject(terminalAuthority.context)
      || typeof terminalAuthority.readMarker !== 'function'
      || terminalAuthority.context.authority?.commit !== authoritySha
      || terminalAuthority.context.generations?.controller !== controllerGenerationId)) fail('TERMINAL_TAIL_AUTHORITY');
  const status = async () => {
    let state = 'INIT';
    for (const [initial, event, next] of Object.entries(TRANSITIONS).map(([initial, [event, next]]) => [initial, event, next])) {
      if (state !== initial) break;
      if (!(await readPrivateJson(eventPath(event), true))) break;
      state = next;
    }
    return { state, raw_values: false };
  };
  return {
    append: async (record) => writeOnceJson(eventPath(record?.event), record),
    load: async (event) => readPrivateJson(eventPath(event), true),
    appendClaim: async (claim) => writeOnceJson(path.join(claimsRoot, `${claimName(claim)}.json`), claim),
    loadClaim: async (kind) => readPrivateJson(path.join(claimsRoot, `${kind}.json`), true),
    appendResult: async (result) => writeOnceJson(path.join(resultsRoot, `${resultName(result)}.json`), result),
    loadResult: async (kind) => readPrivateJson(path.join(resultsRoot, `${kind}.json`), true),
    appendPhaseClaim: async (claim) => {
      if (claim?.purpose !== 'CI3_MAC_PHASE_CLAIM_V1' || !DURABLE_PHASES.includes(claim.phase)) fail('PHASE_CLAIM');
      return writeOnceJson(path.join(claimsRoot, `phase-${claim.phase}.json`), claim);
    },
    loadPhaseClaim: async (phase) => {
      if (!DURABLE_PHASES.includes(phase)) fail('PHASE_CLAIM');
      return readPrivateJson(path.join(claimsRoot, `phase-${phase}.json`), true);
    },
    appendPhaseResult: async (result) => {
      if (result?.purpose !== 'CI3_MAC_PHASE_RESULT_V1' || !DURABLE_PHASES.includes(result.phase)) fail('PHASE_RESULT');
      return writeOnceJson(path.join(resultsRoot, `phase-${result.phase}.json`), result);
    },
    loadPhaseResult: async (phase) => {
      if (!DURABLE_PHASES.includes(phase)) fail('PHASE_RESULT');
      return readPrivateJson(path.join(resultsRoot, `phase-${phase}.json`), true);
    },
    settlePhaseReceipt: async (phase, claimSha256, result, observation) => {
      if (!DURABLE_PHASES.includes(phase)) fail('PHASE_RECEIPT');
      requireSha(claimSha256, 'PHASE_RECEIPT');
      validatePhysicalEffectObservation(observation, phase);
      const receipt = {
        schema_version: 1, purpose: 'CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1', phase,
        claim_sha256: claimSha256, result: result ?? {}, result_sha256: sha256(canonicalJson(result ?? {})),
        observation, raw_values: false,
      };
      const receiptPath = path.join(receiptsRoot, `phase-${phase}.json`);
      await writeOnceJson(receiptPath, receipt);
      const observed = await readBoundLocalFile(receiptPath, { code: 'PHASE_RECEIPT', modes: [0o600] });
      return {
        result: receipt.result, receiptSha256: sha256(observed.bytes),
        physicalObservationSha256: observation.observation_sha256,
        observation,
      };
    },
    reobservePhaseReceipt: async (phase, claimSha256) => {
      if (!DURABLE_PHASES.includes(phase)) fail('PHASE_RECEIPT');
      const receiptPath = path.join(receiptsRoot, `phase-${phase}.json`);
      const existing = await readPrivateJson(receiptPath, true);
      if (!existing) return null;
      exactKeys(existing, ['claim_sha256', 'observation', 'phase', 'purpose', 'raw_values', 'result', 'result_sha256', 'schema_version'], 'PHASE_RECEIPT');
      if (existing.schema_version !== 1 || existing.purpose !== 'CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1'
          || existing.phase !== phase || existing.claim_sha256 !== claimSha256
          || existing.result_sha256 !== sha256(canonicalJson(existing.result ?? {})) || existing.raw_values !== false) fail('PHASE_RECEIPT');
      validatePhysicalEffectObservation(existing.observation, phase);
      const observed = await readBoundLocalFile(receiptPath, { code: 'PHASE_RECEIPT', modes: [0o600] });
      return {
        result: existing.result, receiptSha256: sha256(observed.bytes),
        physicalObservationSha256: existing.observation.observation_sha256,
        observation: existing.observation,
      };
    },
    terminalStatus: async () => {
      const current = await status();
      if (current.state !== 'COMPLETE') return current;
      if (terminalAuthority === null) return { state: 'PRE_TERMINAL_UNPUBLISHED', raw_values: false };
      const observed = await terminalAuthority.readMarker();
      if (observed === null) return { state: 'PRE_TERMINAL_UNPUBLISHED', raw_values: false };
      if (!isPlainObject(observed) || !isPlainObject(observed.marker)
          || !isPlainObject(observed.inputs) || !isPlainObject(observed.paths)) fail('TERMINAL_TAIL_AUTHORITY');
      validatePrivilegedTerminalPassCorpus({
        marker: observed.marker, context: terminalAuthority.context,
        paths: observed.paths, ...observed.inputs,
      });
      return { state: 'TERMINAL_PASS', raw_values: false };
    },
    paths: Object.freeze({
      generationRoot,
      phaseClaim: (phase) => path.join(claimsRoot, `phase-${phase}.json`),
      phaseReceipt: (phase) => path.join(receiptsRoot, `phase-${phase}.json`),
      phaseResult: (phase) => path.join(resultsRoot, `phase-${phase}.json`),
      event: (event) => eventPath(event),
      claim: (kind) => {
        if (!['bootstrap', 'receipt', 'config', 'credential'].includes(kind)) fail('JOURNAL_CLAIM');
        return path.join(claimsRoot, `${kind}.json`);
      },
      result: (kind) => {
        if (!['receipt', 'config', 'credential'].includes(kind)) fail('JOURNAL_RESULT');
        return path.join(resultsRoot, `${kind}.json`);
      },
    }),
    status,
  };
}

const TRANSITIONS = Object.freeze({
  INIT: ['VERIFY_AUTHORITY', 'AUTHORITY_VERIFIED'],
  AUTHORITY_VERIFIED: ['VERIFY_WORKTREE', 'WORKTREE_VERIFIED'],
  WORKTREE_VERIFIED: ['VERIFY_SIMULATOR', 'SIMULATOR_VERIFIED'],
  SIMULATOR_VERIFIED: ['VERIFY_SSH', 'SSH_VERIFIED'],
  SSH_VERIFIED: ['READ_RECEIPT', 'RECEIPT_FETCHED'],
  RECEIPT_FETCHED: ['READ_CONFIG', 'CONFIG_FETCHED'],
  CONFIG_FETCHED: ['READ_CREDENTIAL', 'CREDENTIAL_FETCHED'],
  CREDENTIAL_FETCHED: ['PUBLISH_LOCAL', 'LOCAL_PUBLISHED'],
  LOCAL_PUBLISHED: ['INSTALL_SIMULATOR', 'INSTALLED'],
  INSTALLED: ['REMOVE_CREDENTIAL', 'CREDENTIAL_REMOVED'],
  CREDENTIAL_REMOVED: ['RUN_SCANS', 'SCANNED'],
  SCANNED: ['COMPLETE', 'COMPLETE'],
});

export function advanceProtocol(state, event) {
  const transition = TRANSITIONS[state];
  if (!transition || transition[0] !== event) fail('PROTOCOL_TRANSITION');
  return transition[1];
}

function validatePrivilegedWriterMarkerProof(writer) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  if (!isPlainObject(writer) || writer.marker_verified !== true
      || writer.terminal_state !== 'TERMINAL_PASS') fail(code);
  requireSha(writer.marker_sha256, code);
  return true;
}

export async function runPrivilegedTerminalRecovery({
  recovery, observe, waitForAuthorizedSupervisor,
} = {}) {
  const code = 'TERMINAL_TAIL_AUTHORITY';
  if (recovery !== true || typeof observe !== 'function'
      || typeof waitForAuthorizedSupervisor !== 'function') fail(code);
  const validateSettled = (observed) => {
    if (!isPlainObject(observed) || observed.state !== 'SETTLED'
        || observed.marker_verified !== true
        || observed.terminal_state !== 'TERMINAL_PASS') fail(code);
    requireSha(observed.marker_sha256, code);
    return observed;
  };
  const before = await observe();
  if (before?.state === 'SETTLED') {
    return { ...validateSettled(before), effect_executions: 0, admin_prompts: 0 };
  }
  if (!isPlainObject(before) || before.state !== 'RECOVERABLE'
      || before.marker_verified !== false
      || before.terminal_state !== 'PRE_TERMINAL_UNPUBLISHED') fail(code);
  const invocation = await waitForAuthorizedSupervisor({ recovery: true });
  if (!isPlainObject(invocation)
      || !Number.isSafeInteger(invocation.effect_executions)
      || !Number.isSafeInteger(invocation.admin_prompts)
      || invocation.effect_executions < 0 || invocation.effect_executions > 1
      || invocation.admin_prompts < 0 || invocation.admin_prompts > 1) fail(code);
  const afterObservation = await observe();
  if (afterObservation?.state !== 'SETTLED') fail('STOP_PRE_AUTHORITY');
  const after = validateSettled(afterObservation);
  return {
    ...after,
    effect_executions: invocation.effect_executions,
    admin_prompts: invocation.admin_prompts,
  };
}

export async function runProtocol({ adapters, context, journal, stopAfter = 'COMPLETE' }) {
  let state = 'INIT';
  const allowedStops = new Set([
    'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
    'READ_RECEIPT', 'READ_CONFIG', 'READ_CREDENTIAL', 'PUBLISH_LOCAL',
    'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS', 'INVOKE_WRITER',
    'VERIFY_ANCHOR', 'COMPLETE',
  ]);
  if (!allowedStops.has(stopAfter)) fail('PROTOCOL_TARGET');
  const readResults = [];
  let scans = [];
  let settlement = null;
  let predecessorResultSha256 = '0'.repeat(64);
  const outcome = () => ({ state, scans, readResults, settlement });
  const advance = async (event, operation) => {
    const usesPhaseLedger = DURABLE_PHASES.includes(event);
    const contractSha256 = sha256(canonicalJson({
      event,
      authority_sha: context.authority.commit,
      controller_generation_id: context.generations.controller,
      generations: context.generations,
      predecessor_result_sha256: predecessorResultSha256,
    }));
    let phaseClaim;
    let phaseClaimSha256;
    let priorPhaseClaim;
    let priorPhaseResult;
    if (usesPhaseLedger) {
      phaseClaim = buildPhaseClaim({
        phase: event,
        authoritySha: context.authority.commit,
        controllerGenerationId: context.generations.controller,
        predecessorResultSha256,
        contractSha256,
      });
      priorPhaseClaim = await journal?.loadPhaseClaim?.(event);
      priorPhaseResult = await journal?.loadPhaseResult?.(event);
      if (priorPhaseClaim && !canonicalJson(priorPhaseClaim).equals(canonicalJson(phaseClaim))) fail('JOURNAL_DIVERGENT_EXISTING');
      if (!priorPhaseClaim && priorPhaseResult) fail('REJECT_UNCLAIMED_EXISTING_STATE');
      if (!priorPhaseClaim) await adapters.preflightPhase?.({ event, context });
      const appendClaim = journal?.appendPhaseClaim ?? journal?.appendClaim;
      phaseClaimSha256 = await appendClaim?.(phaseClaim) ?? sha256(canonicalJson(phaseClaim));
      if (priorPhaseClaim && !priorPhaseResult && !(await journal?.load?.(event))) {
        if (!adapters.recoverPhase) fail('CLAIM_CONSUMED_NO_RESULT');
      }
    }
    const existing = await journal?.load?.(event);
    if (existing) {
      const nextState = advanceProtocol(state, event);
      exactKeys(existing, ['event', 'result', 'result_sha256', 'state'], 'JOURNAL_EVENT');
      if (existing.event !== event || existing.state !== nextState
          || existing.result_sha256 !== sha256(canonicalJson(existing.result))) fail('JOURNAL_EVENT');
      state = nextState;
      if (usesPhaseLedger) {
        if (!priorPhaseResult || priorPhaseResult.claim_sha256 !== phaseClaimSha256) fail('JOURNAL_INCOMPLETE_PHASE');
        const persisted = await journal?.reobservePhaseReceipt?.(event, phaseClaimSha256);
        if (!persisted?.observation || typeof adapters.observePhase !== 'function'
            || persisted.physicalObservationSha256 !== priorPhaseResult.physical_observation_sha256) {
          fail('JOURNAL_INCOMPLETE_PHASE');
        }
        await recoverSettledPhase({
          persistedObservation: persisted.observation,
          reobserve: () => adapters.observePhase({ event, result: persisted.result, context, recovery: true }),
        });
        predecessorResultSha256 = sha256(canonicalJson(priorPhaseResult));
      }
      return existing.result;
    }
    let settlement;
    if (!usesPhaseLedger) {
      settlement = { result: await operation({ recovery: false }) };
    } else if (priorPhaseClaim) {
      const persisted = (await journal?.reobservePhaseReceipt?.(event, phaseClaimSha256))
        ?? await adapters.recoverPhase?.({ event, claim: phaseClaim, result: priorPhaseResult });
      if (!persisted?.observation || typeof adapters.observePhase !== 'function') fail('CLAIM_CONSUMED_NO_RESULT');
      await recoverSettledPhase({
        persistedObservation: persisted.observation,
        reobserve: () => adapters.observePhase({ event, result: persisted.result, context, recovery: true }),
      });
      settlement = persisted;
    } else {
      const produced = await operation({ recovery: false, claimCreated: true });
      if (typeof adapters.observePhase !== 'function') fail('PHASE_PHYSICAL_OBSERVATION');
      const observation = await adapters.observePhase({ event, result: produced, context, recovery: false });
      validatePhysicalEffectObservation(observation, event);
      settlement = await journal?.settlePhaseReceipt?.(event, phaseClaimSha256, produced, observation);
      if (!settlement) {
        const receiptBytes = canonicalJson({ event, result: produced ?? {}, synthetic_only: true });
        settlement = {
          result: produced ?? {}, receiptSha256: sha256(receiptBytes),
          physicalObservationSha256: observation.observation_sha256,
          observation,
        };
      }
    }
    const result = settlement.result;
    if (usesPhaseLedger) {
      if (priorPhaseResult && (priorPhaseResult.receipt_sha256 !== settlement.receiptSha256
          || priorPhaseResult.physical_observation_sha256 !== settlement.physicalObservationSha256)) fail('PHASE_RECOVERY_DIVERGENCE');
      const phaseResult = buildPhaseResult({
        phase: event,
        claimSha256: phaseClaimSha256,
        receiptSha256: settlement.receiptSha256,
        physicalObservationSha256: settlement.physicalObservationSha256,
      });
      const appendResult = journal?.appendPhaseResult ?? journal?.appendResult;
      await appendResult?.(phaseResult);
      predecessorResultSha256 = sha256(canonicalJson(phaseResult));
    }
    state = advanceProtocol(state, event);
    await journal?.append?.({ event, state, result: result ?? {}, result_sha256: sha256(canonicalJson(result ?? {})) });
    return result;
  };
  await advance('VERIFY_AUTHORITY', () => adapters.verifyAuthority(context));
  if (stopAfter === 'VERIFY_AUTHORITY') return outcome();
  await advance('VERIFY_WORKTREE', () => adapters.verifyWorktree(context));
  if (stopAfter === 'VERIFY_WORKTREE') return outcome();
  const simulator = await advance('VERIFY_SIMULATOR', (phase) => adapters.verifySimulator(context, phase));
  validateSimulatorGateReceipt(simulator.receipt);
  if (stopAfter === 'VERIFY_SIMULATOR') return outcome();
  const ssh = await advance('VERIFY_SSH', () => adapters.verifySsh(context));
  if (stopAfter === 'VERIFY_SSH') return outcome();
  const bootstrap = buildBootstrapClaim({ ...context, simulator_gate_sha256: sha256(canonicalJson(simulator.receipt)), ssh: ssh.provenance });
  const bootstrapHash = await journal.appendClaim(bootstrap);
  for (const [kind, event] of [['receipt', 'READ_RECEIPT'], ['config', 'READ_CONFIG'], ['credential', 'READ_CREDENTIAL']]) {
    const priorClaim = await journal?.loadClaim?.(kind);
    const priorEvent = await journal?.load?.(event);
    const priorResult = await journal?.loadResult?.(kind);
    if (!priorClaim && (priorEvent || priorResult)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
    if (!priorEvent && priorResult) fail('JOURNAL_INCOMPLETE_READ');
    if (priorClaim && !priorEvent && !priorResult && !adapters.recoverRemote) fail('CLAIM_CONSUMED_NO_RESULT');
    const claim = buildReadClaim({
      kind,
      bootstrapClaimSha256: bootstrapHash,
      expectedPathSha256: context.remote[`${kind}_path_sha256`],
      expectedSha256: context.remote[`${kind}_sha256`],
      remoteGenerationId: kind === 'receipt' ? null : context.generations.remote,
      ssh: ssh.provenance,
    });
    const claimHash = await journal.appendClaim(claim);
    if (priorClaim && !canonicalJson(priorClaim).equals(canonicalJson(claim))) fail('JOURNAL_DIVERGENT_EXISTING');
    const captured = await advance(event, () => priorClaim
      ? adapters.recoverRemote({ kind, claim, context })
      : adapters.readRemote({ kind, claim, context }));
    const result = buildReadResult({ ...captured, kind, claimSha256: claimHash, sshEffectiveConfigSha256: ssh.provenance.effective_config_sha256, sshTrustDescriptorSha256: ssh.provenance.trust_descriptor_sha256, remoteGenerationId: context.generations.remote });
    await journal.appendResult(result);
    if (priorResult && !canonicalJson(priorResult).equals(canonicalJson(result))) fail('JOURNAL_DIVERGENT_EXISTING');
    readResults.push(result);
    if (stopAfter === event) return outcome();
  }
  const local = await advance('PUBLISH_LOCAL', ({ recovery, claimCreated } = {}) => adapters.publishLocal({ context, readResults, simulator, ssh, recovery, claimCreated }));
  if (stopAfter === 'PUBLISH_LOCAL') return outcome();
  const installed = await advance('INSTALL_SIMULATOR', ({ recovery, claimCreated } = {}) => adapters.installSimulator({ context, local, simulator, recovery, claimCreated }));
  if (stopAfter === 'INSTALL_SIMULATOR') return outcome();
  await advance('REMOVE_CREDENTIAL', ({ recovery } = {}) => adapters.removeSimulatorCredential({ context, installed, simulator, recovery }));
  if (stopAfter === 'REMOVE_CREDENTIAL') return outcome();
  scans = await advance('RUN_SCANS', ({ recovery } = {}) => adapters.scan({ context, installed, local, readResults, simulator, ssh, recovery }));
  validateScanIds(scans.map(({ scan_id: scanId }) => scanId));
  for (let index = 0; index < scans.length; index += 1) validateScanReceipt(scans[index], TERMINAL_SCAN_IDS[index]);
  if (stopAfter === 'RUN_SCANS') return outcome();
  // The normal executor can only seal a pre-terminal journal.  The COMPLETE
  // object is a deterministic commit contract, not a PASS claim.  It is
  // persisted before the one privileged invocation so every normal byte is in
  // the reversible frame; no journal mutation is permitted after the writer.
  const terminalCommit = {
    terminal_commit_contract_sha256: sha256(canonicalJson({
      authority_sha: context.authority.commit,
      generations: context.generations,
      run_scans_sha256: sha256(canonicalJson(scans)),
      privileged_phases: TERMINAL_SETTLEMENT_PHASES,
      marker_last: true,
    })),
  };
  const completeRecord = {
    event: 'COMPLETE', state: 'COMPLETE', result: terminalCommit,
    result_sha256: sha256(canonicalJson(terminalCommit)),
  };
  const priorComplete = await journal?.load?.('COMPLETE');
  if (priorComplete && !canonicalJson(priorComplete).equals(canonicalJson(completeRecord))) fail('JOURNAL_DIVERGENT_EXISTING');
  if (!priorComplete) await journal?.append?.(completeRecord);
  state = 'COMPLETE';
  await adapters.finalizeTerminalEvidence?.({ context, installed, local, readResults, scans, simulator, ssh });
  if (typeof adapters.invokeWriter !== 'function') fail('TERMINAL_SETTLEMENT');
  const writer = await adapters.invokeWriter({
    context, installed, local, readResults, scans, simulator, ssh,
    recovery: priorComplete !== null && priorComplete !== undefined,
  });
  validatePrivilegedWriterMarkerProof(writer);
  settlement = writer?.settlement;
  validateTerminalSettlementReceipt(settlement);
  if (settlement.authority_sha !== context.authority.commit
      || settlement.terminal_generation_id !== context.generations.terminal
      || settlement.pre_anchor_sha256 !== (writer.pre_anchor_sha256 ?? writer.anchor_sha256)
      || writer.terminal_state !== 'TERMINAL_PASS') fail('TERMINAL_SETTLEMENT');
  return outcome();
}

export async function dispatchControllerMode({ mode, adapters, context, journal }) {
  parseControllerMode([mode]);
  if (mode === '--self-test') fail('MODE_INVALID');
  if (mode === '--terminalize-tail') {
    const receipt = await adapters.terminalizeTail();
    if (receipt?.terminal_state !== 'TERMINAL_PASS'
        || receipt.receipt_is_commit_marker !== true || receipt.raw_values !== false) fail('TERMINAL_TAIL');
    return { mode, state: 'TERMINAL_PASS', raw_values: false };
  }
  if (mode === 'publish-vps-operation-authority-pass') {
    const published = await adapters.publishVpsOperationAuthorityPass();
    if (published?.status !== 'CREATED' || published.raw_values !== false) fail('VPS_PUBLISHER0');
    return { mode, state: 'VPS_OPERATION_AUTHORITY_PASS_PUBLISHED', raw_values: false };
  }
  if (mode === 'publish-operation-authority') {
    const published = await adapters.publishOperationAuthority();
    if (published?.status !== 'CREATED' || published.raw_values !== false) fail('OPERATION_AUTHORITY_PUBLISHER');
    return { mode, state: 'OPERATION_AUTHORITY_PUBLISHED', raw_values: false };
  }
  if (mode === 'publish-privileged-writer-authority') {
    const published = await adapters.publishPrivilegedWriterAuthority();
    if (published?.status !== 'CREATED' || published.raw_values !== false) fail('PRIVILEGED_AUTHORITY_PUBLISHER');
    return { mode, state: 'PRIVILEGED_WRITER_AUTHORITY_PUBLISHED', raw_values: false };
  }
  if (mode === 'status') {
    const status = typeof journal.terminalStatus === 'function'
      ? await journal.terminalStatus()
      : await journal.status();
    if (!isPlainObject(status) || status.raw_values !== false || typeof status.state !== 'string') fail('STATUS_RECEIPT');
    return { mode, state: status.state, raw_values: false };
  }
  const stopAfterByMode = {
    plan: 'VERIFY_WORKTREE',
    'verify-simulator': 'VERIFY_SIMULATOR',
    'verify-ssh': 'VERIFY_SSH',
    fetch: 'PUBLISH_LOCAL',
    'install-simulator': 'REMOVE_CREDENTIAL',
    scan: 'RUN_SCANS',
    'write-terminal-anchor': 'VERIFY_ANCHOR',
    resume: 'COMPLETE',
  };
  const result = await runProtocol({ adapters, context, journal, stopAfter: stopAfterByMode[mode] });
  let reportedState = result.state;
  if (mode === 'resume' && result.state === 'COMPLETE') {
    if (typeof journal.terminalStatus !== 'function') {
      reportedState = 'PRE_TERMINAL_UNPUBLISHED';
    } else {
      const terminalStatus = await journal.terminalStatus();
      if (!isPlainObject(terminalStatus) || terminalStatus.raw_values !== false
          || !['PRE_TERMINAL_UNPUBLISHED', 'TERMINAL_PASS'].includes(terminalStatus.state)) {
        fail('STATUS_RECEIPT');
      }
      reportedState = terminalStatus.state;
    }
  }
  return {
    mode,
    state: reportedState,
    raw_values: false,
  };
}

function shellQuote(value) {
  if (typeof value !== 'string' || value.includes('\0') || value.includes('\n') || value.includes('\r')) fail('OPERATION_AUTHORITY_PUBLISHER');
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

function appleScriptString(value) {
  return `"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;
}

function runAdminPublisher(shellScript, code) {
  const closedShellScript = `/usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin /bin/sh -c ${shellQuote(shellScript)}`;
  const result = spawnSync('/usr/bin/osascript', [
    '-e', `do shell script ${appleScriptString(closedShellScript)} with administrator privileges`,
  ], {
    encoding: null, env: CLOSED_BOOTSTRAP_ENVIRONMENT,
    stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024, timeout: 120000,
  });
  if (result.status !== 0 || result.signal || result.error
      || result.stderr.length !== 0 || result.stdout.toString('utf8').trim() !== `${code} PASS`) fail(code);
}

export function validatePublisherHumanAuthorizationReceipt(record, expected) {
  const code = 'OPERATION_AUTHORITY_PUBLISHER';
  exactKeys(record, [
    'approved_action', 'attempt', 'authority_manifest_sha256', 'authority_sha',
    'node_binary_sha256', 'operation_authority_sha256', 'publisher_input_manifest_sha256',
    'purpose', 'raw_values', 'retry', 'schema_version',
    'vps_operation_authority_pass_sha256',
  ], code);
  exactKeys(expected, [
    'authorityManifestSha256', 'authoritySha', 'nodeBinarySha256',
    'operationAuthoritySha256', 'publisherInputManifestSha256',
    'vpsOperationAuthorityPassSha256',
  ], code);
  if (record.schema_version !== 1
      || record.purpose !== 'CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V1'
      || record.approved_action !== 'PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY'
      || record.authority_sha !== expected.authoritySha
      || record.authority_manifest_sha256 !== expected.authorityManifestSha256
      || record.node_binary_sha256 !== expected.nodeBinarySha256
      || record.operation_authority_sha256 !== expected.operationAuthoritySha256
      || record.publisher_input_manifest_sha256 !== expected.publisherInputManifestSha256
      || record.vps_operation_authority_pass_sha256 !== expected.vpsOperationAuthorityPassSha256
      || record.attempt !== 1 || record.retry !== false || record.raw_values !== false) fail(code);
  return true;
}

export const EXTERNAL_OPERATIONAL_LAUNCHER_MODES = Object.freeze([
  'plan', 'verify-simulator', 'verify-ssh', 'fetch', 'install-simulator', 'scan',
  'write-terminal-anchor', 'resume', 'status', 'publish-privileged-writer-authority',
]);

export function buildExternalLauncherAuthority({
  authoritySha, controllerGenerationId, nodeSha256, controllerSha256, launcherSha256,
  launchAttestationSha256, authorityManifestSha256, allowedModes,
} = {}) {
  requireSha(authoritySha, 'EXTERNAL_LAUNCHER_AUTHORITY', [40]);
  validateGenerationId(controllerGenerationId);
  for (const value of [
    nodeSha256, controllerSha256, launcherSha256, launchAttestationSha256, authorityManifestSha256,
  ]) requireSha(value, 'EXTERNAL_LAUNCHER_AUTHORITY');
  if (!Array.isArray(allowedModes) || allowedModes.length === 0
      || new Set(allowedModes).size !== allowedModes.length
      || allowedModes.some((mode) => ![
        '--self-test', 'plan', 'verify-simulator', 'verify-ssh', 'fetch', 'install-simulator',
        'scan', 'write-terminal-anchor', 'resume', 'status', 'publish-vps-operation-authority-pass',
        'publish-operation-authority', 'publish-privileged-writer-authority',
      ].includes(mode))) fail('EXTERNAL_LAUNCHER_AUTHORITY');
  return Buffer.from([
    'CI3_EXTERNAL_LAUNCHER_AUTHORITY_V1',
    `authority_sha ${authoritySha}`,
    `controller_generation_id ${controllerGenerationId}`,
    `node_sha256 ${nodeSha256}`,
    `controller_sha256 ${controllerSha256}`,
    `launcher_sha256 ${launcherSha256}`,
    `launch_attestation_sha256 ${launchAttestationSha256}`,
    `authority_manifest_sha256 ${authorityManifestSha256}`,
    `allowed_modes ${allowedModes.join(',')}`,
    'raw_values false',
    '',
  ].join('\n'));
}

export function validateExternalLauncherAuthority(bytes, expected) {
  if (!Buffer.isBuffer(bytes) || !bytes.equals(buildExternalLauncherAuthority(expected))) {
    fail('EXTERNAL_LAUNCHER_AUTHORITY');
  }
  return true;
}

export function buildPublisherInstallationContract({ authoritySha, controllerGenerationId } = {}) {
  requireSha(authoritySha, 'OPERATION_AUTHORITY_PUBLISHER', [40]);
  validateGenerationId(controllerGenerationId);
  const versionRoot = path.join(
    '/Library/Application Support/Agentempp/ci3-controller-authority', authoritySha,
  );
  const runtimeRoot = path.join(versionRoot, 'runtime');
  const sshRoot = path.join(versionRoot, 'ssh-snapshots', controllerGenerationId);
  const targets = {
    'node-runtime': { path: path.join(runtimeRoot, 'node'), mode: 0o555 },
    controller: { path: path.join(runtimeRoot, 'ci3-bridge-controller.mjs'), mode: 0o555 },
    'launcher-runtime': { path: path.join(runtimeRoot, 'ci3-bridge-launcher.zsh'), mode: 0o555 },
    'launcher-bootstrap-authority': { path: path.join(runtimeRoot, 'launcher-bootstrap.authority.v1'), mode: 0o444 },
    'launch-attestation': { path: path.join(runtimeRoot, 'launch-attestation.json'), mode: 0o444 },
    'authority-manifest': { path: path.join(runtimeRoot, 'authority-manifest.v1'), mode: 0o444 },
    'operation-authority': { path: path.join(versionRoot, 'mac-operation-authority.v1.json'), mode: 0o444 },
    'human-authorization': { path: path.join(versionRoot, 'human-authorization.receipt.json'), mode: 0o444 },
    'vps-pass': { path: path.join(versionRoot, 'vps-operation-authority.pass.json'), mode: 0o444 },
    'vps-issuer-authority': { path: path.join(versionRoot, 'vps-issuer-authority.receipt.json'), mode: 0o444 },
    'publisher-input-manifest': { path: path.join(versionRoot, 'publisher-input.manifest.json'), mode: 0o444 },
    'ssh-config': { path: path.join(sshRoot, 'ssh_config'), mode: 0o444 },
    'ssh-known-hosts': { path: path.join(sshRoot, 'known_hosts'), mode: 0o444 },
    'ssh-private-key': { path: path.join(sshRoot, 'id_ed25519'), mode: 0o400 },
    'ssh-public-key': { path: path.join(sshRoot, 'id_ed25519.pub'), mode: 0o444 },
    'ssh-trust-descriptor': { path: path.join(sshRoot, 'trust-descriptor.json'), mode: 0o444 },
  };
  return {
    version_root: versionRoot,
    runtime_root: runtimeRoot,
    ssh_root: sshRoot,
    targets,
    ssh: {
      config: targets['ssh-config'], known_hosts: targets['ssh-known-hosts'],
      identity: targets['ssh-private-key'], public_key: targets['ssh-public-key'],
      trust_descriptor: targets['ssh-trust-descriptor'],
    },
  };
}

const PUBLISHER_TRANSPORT_ROLES = Object.freeze([
  'node-runtime', 'controller', 'launcher-runtime', 'launch-attestation', 'authority-manifest',
  'operation-authority', 'ssh-config', 'ssh-known-hosts', 'ssh-private-key',
  'ssh-public-key', 'ssh-trust-descriptor',
]);

export function validatePublisherTransportManifest(manifest, expected) {
  const code = 'OPERATION_AUTHORITY_PUBLISHER';
  if (!isPlainObject(manifest) || !isPlainObject(expected)) fail(code);
  exactKeys(manifest, [
    'authority_sha', 'collector_contracts_sha256', 'controller_generation_id', 'entries',
    'purpose', 'raw_values', 'remote_generation_id', 'schema_version',
    'transfer_payload_sha256',
  ], code);
  exactKeys(expected, [
    'authoritySha', 'collectorContractsSha256', 'controllerGenerationId',
    'entries', 'remoteGenerationId',
  ], code);
  const roles = manifest.entries?.map(({ role }) => role);
  if (manifest.schema_version !== 1 || manifest.purpose !== 'CI3_VPS_PUBLISHER_INPUT_MANIFEST_V2'
      || manifest.authority_sha !== expected.authoritySha
      || manifest.remote_generation_id !== expected.remoteGenerationId
      || manifest.controller_generation_id !== expected.controllerGenerationId
      || manifest.collector_contracts_sha256 !== expected.collectorContractsSha256
      || manifest.raw_values !== false || !Array.isArray(manifest.entries)
      || JSON.stringify(roles) !== JSON.stringify(PUBLISHER_TRANSPORT_ROLES)
      || !canonicalJson(manifest.entries).equals(canonicalJson(expected.entries))
      || manifest.transfer_payload_sha256 !== sha256(canonicalJson(manifest.entries))) fail(code);
  for (const entry of manifest.entries) {
    exactKeys(entry, ['path_sha256', 'role', 'sha256'], code);
    requireSha(entry.path_sha256, code);
    requireSha(entry.sha256, code);
  }
  return true;
}

export async function verifyInstalledPublisherTargets({ expectedSha256ByRole, readTarget } = {}) {
  const code = 'OPERATION_AUTHORITY_PUBLISHER';
  const roles = [
    'node-runtime', 'controller', 'launcher-runtime', 'launcher-bootstrap-authority',
    'launch-attestation', 'authority-manifest',
    'operation-authority', 'human-authorization', 'vps-pass', 'vps-issuer-authority',
    'publisher-input-manifest', 'ssh-config', 'ssh-known-hosts', 'ssh-private-key',
    'ssh-public-key', 'ssh-trust-descriptor',
  ];
  exactKeys(expectedSha256ByRole, roles, code);
  if (typeof readTarget !== 'function') fail(code);
  for (const role of roles) {
    requireSha(expectedSha256ByRole[role], code);
    let observed;
    try { observed = await readTarget(role); } catch { fail(code); }
    if (!isPlainObject(observed) || !Buffer.isBuffer(observed.bytes)
        || sha256(observed.bytes) !== expectedSha256ByRole[role]
        || observed.immutable !== true) fail(code);
    const expectedMode = ['node-runtime', 'controller', 'launcher-runtime'].includes(role)
      ? 0o555 : role === 'ssh-private-key' ? 0o400 : 0o444;
    const physical = observed.metadata;
    if (!isPlainObject(physical) || physical.uid !== 0 || physical.gid !== 0
        || (physical.mode & 0o777) !== expectedMode || physical.nlink !== 1) fail(code);
  }
  return true;
}

export function buildPublisher1TransactionRequest({
  context, receiverRoot, receiverManifestSha256, shaByRole, sourceObservationsByRole,
} = {}) {
  const code = 'OPERATION_AUTHORITY_PUBLISHER';
  validateTerminalPassContext(context, code);
  requireSha(receiverManifestSha256, code);
  const installation = buildPublisherInstallationContract({
    authoritySha: context.authority.commit,
    controllerGenerationId: context.generations.controller,
  });
  const expectedReceiverRootSuffix = path.join(
    'receiver', context.generations.remote, context.generations.controller, receiverManifestSha256,
  );
  if (!path.isAbsolute(receiverRoot ?? '') || receiverRoot.includes('/../')
      || !receiverRoot.endsWith(expectedReceiverRootSuffix)) fail(code);
  exactKeys(shaByRole, Object.keys(installation.targets), code);
  exactKeys(sourceObservationsByRole, Object.keys(installation.targets), code);
  const entries = Object.entries(installation.targets).map(([role, target]) => {
    requireSha(shaByRole[role], code);
    const sourcePath = path.join(receiverRoot, `${role}.payload`);
    const observed = sourceObservationsByRole[role];
    exactKeys(observed, [
      'dev', 'gid', 'identity_sha256', 'ino', 'mode', 'mtime_ns', 'nlink', 'path',
      'path_sha256', 'role', 'sha256', 'size', 'uid',
    ], code);
    for (const field of ['path_sha256', 'sha256', 'identity_sha256']) requireSha(observed[field], code);
    const physical = {
      uid: observed.uid, gid: observed.gid, mode: observed.mode, nlink: observed.nlink,
      size: observed.size, mtime_ns: observed.mtime_ns, dev: observed.dev, ino: observed.ino,
    };
    if (observed.role !== role || observed.path !== sourcePath
        || observed.path_sha256 !== sha256(Buffer.from(sourcePath))
        || observed.sha256 !== shaByRole[role]
        || observed.identity_sha256 !== physicalIdentitySha256(physical)
        || !Number.isInteger(observed.uid) || observed.uid <= 0
        || !Number.isInteger(observed.gid) || observed.gid <= 0
        || observed.mode !== 0o600 || observed.nlink !== 1
        || !Number.isInteger(observed.size) || observed.size < 0
        || typeof observed.mtime_ns !== 'string' || !/^\d+$/.test(observed.mtime_ns)
        || typeof observed.dev !== 'string' || !/^\d+$/.test(observed.dev)
        || typeof observed.ino !== 'string' || !/^\d+$/.test(observed.ino)) fail(code);
    return {
      role,
      source_path: sourcePath,
      source_sha256: shaByRole[role],
      source_path_sha256: observed.path_sha256,
      source_uid: observed.uid, source_gid: observed.gid, source_mode: observed.mode,
      source_nlink: observed.nlink, source_size: observed.size,
      source_mtime_ns: observed.mtime_ns, source_dev: observed.dev, source_ino: observed.ino,
      source_identity_sha256: observed.identity_sha256,
      destination_relative_path: path.relative(installation.version_root, target.path),
      mode: target.mode,
    };
  });
  if (entries.some(({ destination_relative_path: relative }) => relative.startsWith('..') || path.isAbsolute(relative))) fail(code);
  return {
    schema_version: 1,
    purpose: 'CI3_PUBLISHER1_DESCRIPTOR_TRANSACTION_V1',
    authority_sha: context.authority.commit,
    remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
    receiver_root: receiverRoot,
    receiver_manifest_sha256: receiverManifestSha256,
    destination_parent: path.dirname(installation.version_root),
    state_root: path.join(
      '/Library/Application Support/Agentempp/ci3-publisher1-state',
      context.authority.commit, context.generations.controller,
    ),
    entries,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
}

export function validatePublisher1MaterializerAuthorityBinding(authority, expected) {
  const code = 'STOP_PRE_AUTHORITY';
  exactKeys(expected, [
    'authoritySha', 'controllerGenerationId', 'receiverRoot', 'receiverRootIdentitySha256',
    'receiverLeaves',
    'requestGid', 'requestIdentitySha256', 'requestPath', 'requestSha256', 'requestUid',
  ], code);
  exactKeys(authority, [
    'authority_sha', 'controller_generation_id', 'normal_executor_authorized', 'purpose',
    'raw_values', 'receiver_root_identity_sha256', 'receiver_root_path_sha256',
    'receiver_leaves',
    'request_gid', 'request_identity_sha256', 'request_mode', 'request_nlink',
    'request_path_sha256', 'request_sha256', 'request_uid', 'schema_version',
  ], code);
  requireSha(expected.authoritySha, code, [40]);
  validateGenerationId(expected.controllerGenerationId);
  for (const value of [expected.requestSha256, expected.requestIdentitySha256, expected.receiverRootIdentitySha256]) requireSha(value, code);
  if (!Array.isArray(expected.receiverLeaves) || expected.receiverLeaves.length !== 16
      || !Array.isArray(authority.receiver_leaves) || authority.receiver_leaves.length !== 16) fail(code);
  const validateLeaf = (leaf) => {
    exactKeys(leaf, [
      'dev', 'gid', 'identity_sha256', 'ino', 'mode', 'mtime_ns', 'nlink',
      'path_sha256', 'role', 'sha256', 'size', 'uid',
    ], code);
    for (const field of ['path_sha256', 'sha256', 'identity_sha256']) requireSha(leaf[field], code);
    if (typeof leaf.role !== 'string' || leaf.role.length === 0
        || !Number.isInteger(leaf.uid) || leaf.uid <= 0
        || !Number.isInteger(leaf.gid) || leaf.gid <= 0
        || leaf.mode !== 0o600 || leaf.nlink !== 1
        || !Number.isInteger(leaf.size) || leaf.size < 0
        || typeof leaf.mtime_ns !== 'string' || !/^\d+$/.test(leaf.mtime_ns)
        || typeof leaf.dev !== 'string' || !/^\d+$/.test(leaf.dev)
        || typeof leaf.ino !== 'string' || !/^\d+$/.test(leaf.ino)
        || leaf.identity_sha256 !== physicalIdentitySha256({
          uid: leaf.uid, gid: leaf.gid, mode: leaf.mode, nlink: leaf.nlink,
          size: leaf.size, mtime_ns: leaf.mtime_ns, dev: leaf.dev, ino: leaf.ino,
        })) fail(code);
  };
  expected.receiverLeaves.forEach(validateLeaf);
  authority.receiver_leaves.forEach(validateLeaf);
  if (!path.isAbsolute(expected.requestPath ?? '') || !path.isAbsolute(expected.receiverRoot ?? '')
      || expected.requestPath.includes('/../') || expected.receiverRoot.includes('/../')
      || authority.schema_version !== 2
      || authority.purpose !== 'CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2'
      || authority.authority_sha !== expected.authoritySha
      || authority.controller_generation_id !== expected.controllerGenerationId
      || authority.request_path_sha256 !== sha256(Buffer.from(expected.requestPath))
      || authority.request_sha256 !== expected.requestSha256
      || authority.request_identity_sha256 !== expected.requestIdentitySha256
      || authority.request_uid !== expected.requestUid || authority.request_gid !== expected.requestGid
      || authority.request_mode !== 0o600 || authority.request_nlink !== 1
      || authority.receiver_root_path_sha256 !== sha256(Buffer.from(expected.receiverRoot))
      || authority.receiver_root_identity_sha256 !== expected.receiverRootIdentitySha256
      || !canonicalJson(authority.receiver_leaves).equals(canonicalJson(expected.receiverLeaves))
      || authority.normal_executor_authorized !== false || authority.raw_values !== false) fail(code);
  return true;
}

export async function runPublisher1ControllerTransaction({
  expected, observe, invokeAdmin, persistReceipt, afterAdmin = null,
} = {}) {
  const code = 'OPERATION_AUTHORITY_PUBLISHER';
  exactKeys(expected, [
    'authority_sha', 'controller_generation_id', 'receiver_root_sha256', 'request_sha256',
  ], code);
  requireSha(expected.authority_sha, code, [40]);
  validateGenerationId(expected.controller_generation_id);
  requireSha(expected.receiver_root_sha256, code);
  requireSha(expected.request_sha256, code);
  if (typeof observe !== 'function' || typeof invokeAdmin !== 'function' || typeof persistReceipt !== 'function'
      || (afterAdmin !== null && typeof afterAdmin !== 'function')) fail(code);
  const validateSettled = (observed) => {
    if (!isPlainObject(observed) || observed.state !== 'SETTLED'
        || observed.authority_sha !== expected.authority_sha
        || observed.controller_generation_id !== expected.controller_generation_id
        || observed.request_sha256 !== expected.request_sha256
        || observed.receiver_root_sha256 !== expected.receiver_root_sha256
        || observed.tree_verified !== true || observed.raw_values !== false) fail('PUBLISHER1_RECOVERY_STOP');
    requireSha(observed.claim_sha256, 'PUBLISHER1_RECOVERY_STOP');
    requireSha(observed.result_sha256, 'PUBLISHER1_RECOVERY_STOP');
    return observed;
  };
  const before = await observe();
  if (before?.state === 'SETTLED') {
    const settled = validateSettled(before);
    await persistReceipt(settled);
    return { status: 'EXISTS_RECOVERED', raw_values: false };
  }
  if (before?.state !== 'ABSENT') fail('PUBLISHER1_RECOVERY_STOP');
  await invokeAdmin();
  const settled = validateSettled(await observe());
  if (afterAdmin) await afterAdmin(settled);
  await persistReceipt(settled);
  return { status: 'CREATED', raw_values: false };
}

async function readPublisher1MaterializerAuthority(context) {
  const code = 'STOP_PRE_AUTHORITY';
  const bootstrapRoot = path.join(
    '/Library/Application Support/Agentempp/ci3-publisher1-bootstrap',
    context.authority.commit, context.generations.controller,
  );
  const authorityPath = path.join(bootstrapRoot, 'publisher1-materializer.authority.json');
  const binaryPath = path.join(bootstrapRoot, 'runtime', 'ci3-terminal-anchor-writer');
  const authorityBytes = await readRootImmutableFile(authorityPath, null, 0o444, code);
  let authority;
  try { authority = JSON.parse(authorityBytes.bytes.toString('utf8')); } catch { fail(code); }
  exactKeys(authority, [
    'allowed_environment', 'authority_sha', 'controller_generation_id',
    'issuer_authority_sha256', 'materializer_path', 'materializer_path_sha256',
    'materializer_sha256', 'normal_executor_authorized', 'purpose', 'raw_values',
    'receiver_root_identity_sha256', 'receiver_root_path_sha256',
    'receiver_leaves',
    'request_gid', 'request_identity_sha256', 'request_mode', 'request_nlink',
    'request_path_sha256', 'request_sha256', 'request_uid',
    'schema_version', 'writer_source_sha256',
  ], code);
  if (authority.schema_version !== 2
      || authority.purpose !== 'CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2'
      || authority.authority_sha !== context.authority.commit
      || authority.controller_generation_id !== context.generations.controller
      || authority.materializer_path !== binaryPath
      || authority.materializer_path_sha256 !== sha256(Buffer.from(binaryPath))
      || authority.writer_source_sha256 !== context.authority.components.writer.sha256
      || authority.normal_executor_authorized !== false || authority.raw_values !== false
      || !canonicalJson(authority.allowed_environment).equals(canonicalJson(CLOSED_BOOTSTRAP_ENVIRONMENT))) fail(code);
  for (const field of [
    'issuer_authority_sha256', 'materializer_sha256', 'request_path_sha256',
    'request_sha256', 'request_identity_sha256', 'receiver_root_path_sha256',
    'receiver_root_identity_sha256',
  ]) requireSha(authority[field], code);
  if (!Array.isArray(authority.receiver_leaves) || authority.receiver_leaves.length !== 16) fail(code);
  if (!Number.isInteger(authority.request_uid) || authority.request_uid <= 0
      || !Number.isInteger(authority.request_gid) || authority.request_gid <= 0
      || authority.request_mode !== 0o600 || authority.request_nlink !== 1) fail(code);
  const binary = await readRootImmutableFile(binaryPath, authority.materializer_sha256, 0o555, code);
  return { authority, authorityPath, binaryPath, binary };
}

export async function createOperationAuthorityPublisher({ launchAttestation } = {}) {
  validateLaunchAttestation(launchAttestation);
  const requestRoot = path.join(homedir(), '.config/agentempp/ci3/publisher-input', launchAttestation.authority_sha);
  const requestPath = path.join(requestRoot, 'operation-authority.publisher-request.json');
  return {
    publishOperationAuthority: async () => {
      const requestBytes = await readBoundLocalFile(requestPath, { code: 'OPERATION_AUTHORITY_PUBLISHER', modes: [0o600] });
      let request;
      try { request = JSON.parse(requestBytes.bytes.toString('utf8')); } catch { fail('OPERATION_AUTHORITY_PUBLISHER'); }
      exactKeys(request, [
        'attempt', 'authority_candidate_path', 'authority_candidate_sha256', 'authority_sha',
        'authority_manifest_candidate_path', 'authority_manifest_candidate_sha256',
        'controller_candidate_path', 'controller_candidate_sha256',
        'human_authorization_receipt_path', 'human_authorization_receipt_sha256',
        'launch_attestation_candidate_path', 'launch_attestation_candidate_sha256',
        'launcher_candidate_path', 'launcher_candidate_sha256',
        'node_candidate_path', 'node_candidate_sha256',
        'publisher_input_manifest_path', 'publisher_input_manifest_sha256',
        'purpose', 'raw_values', 'retry', 'schema_version',
        'ssh_config_candidate_path', 'ssh_config_candidate_sha256',
        'ssh_known_hosts_candidate_path', 'ssh_known_hosts_candidate_sha256',
        'ssh_private_key_candidate_path', 'ssh_private_key_candidate_sha256',
        'ssh_public_key_candidate_path', 'ssh_public_key_candidate_sha256',
        'ssh_trust_descriptor_candidate_path', 'ssh_trust_descriptor_candidate_sha256',
        'vps_operation_authority_pass_path', 'vps_operation_authority_pass_sha256',
        'vps_issuer_authority_path', 'vps_issuer_authority_sha256',
      ], 'OPERATION_AUTHORITY_PUBLISHER');
      if (request.schema_version !== 1 || request.purpose !== 'CI3_OPERATION_AUTHORITY_PUBLISHER_REQUEST_V1'
          || request.authority_sha !== launchAttestation.authority_sha || request.attempt !== 1
          || request.retry !== false || request.raw_values !== false) fail('OPERATION_AUTHORITY_PUBLISHER');
      for (const field of [
        'authority_candidate_path', 'authority_manifest_candidate_path', 'controller_candidate_path',
        'human_authorization_receipt_path', 'launch_attestation_candidate_path',
        'launcher_candidate_path', 'node_candidate_path',
        'publisher_input_manifest_path', 'vps_operation_authority_pass_path',
        'vps_issuer_authority_path', 'ssh_config_candidate_path', 'ssh_known_hosts_candidate_path',
        'ssh_private_key_candidate_path', 'ssh_public_key_candidate_path',
        'ssh_trust_descriptor_candidate_path',
      ]) {
        if (!path.isAbsolute(request[field]) || request[field].includes('/../')) fail('OPERATION_AUTHORITY_PUBLISHER');
      }
      for (const field of [
        'authority_candidate_sha256', 'authority_manifest_candidate_sha256',
        'controller_candidate_sha256', 'human_authorization_receipt_sha256',
        'launch_attestation_candidate_sha256', 'launcher_candidate_sha256', 'node_candidate_sha256',
        'publisher_input_manifest_sha256', 'vps_operation_authority_pass_sha256',
        'vps_issuer_authority_sha256', 'ssh_config_candidate_sha256',
        'ssh_known_hosts_candidate_sha256', 'ssh_private_key_candidate_sha256',
        'ssh_public_key_candidate_sha256', 'ssh_trust_descriptor_candidate_sha256',
      ]) requireSha(request[field], 'OPERATION_AUTHORITY_PUBLISHER');
      if (request.node_candidate_sha256 !== launchAttestation.tools.node.binary_sha256) fail('OPERATION_AUTHORITY_PUBLISHER');
      const authorityCandidate = await readBoundLocalFile(request.authority_candidate_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.authority_candidate_sha256, modes: [0o600, 0o400] });
      const nodeCandidate = await readBoundLocalFile(request.node_candidate_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.node_candidate_sha256, modes: [0o755, 0o555, 0o700, 0o500] });
      const controllerCandidate = await readBoundLocalFile(request.controller_candidate_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.controller_candidate_sha256, modes: [0o600, 0o400, 0o700, 0o500] });
      const launcherCandidate = await readBoundLocalFile(request.launcher_candidate_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.launcher_candidate_sha256, modes: [0o700, 0o500, 0o600, 0o400] });
      const launchAttestationCandidate = await readBoundLocalFile(request.launch_attestation_candidate_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.launch_attestation_candidate_sha256, modes: [0o600, 0o400] });
      const authorityManifestCandidate = await readBoundLocalFile(request.authority_manifest_candidate_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.authority_manifest_candidate_sha256, modes: [0o600, 0o400] });
      const sshCandidates = {};
      for (const [role, pathField, hashField, modes] of [
        ['ssh-config', 'ssh_config_candidate_path', 'ssh_config_candidate_sha256', [0o600, 0o400]],
        ['ssh-known-hosts', 'ssh_known_hosts_candidate_path', 'ssh_known_hosts_candidate_sha256', [0o600, 0o400]],
        ['ssh-private-key', 'ssh_private_key_candidate_path', 'ssh_private_key_candidate_sha256', [0o600, 0o400]],
        ['ssh-public-key', 'ssh_public_key_candidate_path', 'ssh_public_key_candidate_sha256', [0o600, 0o400]],
        ['ssh-trust-descriptor', 'ssh_trust_descriptor_candidate_path', 'ssh_trust_descriptor_candidate_sha256', [0o600, 0o400]],
      ]) {
        sshCandidates[role] = await readBoundLocalFile(request[pathField], {
          code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request[hashField], modes,
        });
      }
      const humanReceipt = await readBoundLocalFile(request.human_authorization_receipt_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.human_authorization_receipt_sha256, modes: [0o600, 0o400] });
      const publisherInputManifest = await readBoundLocalFile(request.publisher_input_manifest_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.publisher_input_manifest_sha256, modes: [0o600, 0o400] });
      const vpsPass = await readBoundLocalFile(request.vps_operation_authority_pass_path, { code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: request.vps_operation_authority_pass_sha256, modes: [0o600, 0o400] });
      const vpsIssuer = await readRootImmutableFile(
        request.vps_issuer_authority_path, request.vps_issuer_authority_sha256,
        0o444, 'STOP_PRE_AUTHORITY',
      );
      if (!nodeCandidate.bytes.length || !humanReceipt.bytes.length) fail('OPERATION_AUTHORITY_PUBLISHER');
      let authorityRecord;
      let humanAuthorization;
      let inputManifest;
      let vpsPassReceipt;
      let vpsIssuerReceipt;
      let transportedAttestation;
      try { authorityRecord = JSON.parse(authorityCandidate.bytes.toString('utf8')); } catch { fail('OPERATION_AUTHORITY_PUBLISHER'); }
      try { humanAuthorization = JSON.parse(humanReceipt.bytes.toString('utf8')); } catch { fail('OPERATION_AUTHORITY_PUBLISHER'); }
      try { inputManifest = JSON.parse(publisherInputManifest.bytes.toString('utf8')); } catch { fail('OPERATION_AUTHORITY_PUBLISHER'); }
      try { vpsPassReceipt = JSON.parse(vpsPass.bytes.toString('utf8')); } catch { fail('OPERATION_AUTHORITY_PUBLISHER'); }
      try { vpsIssuerReceipt = JSON.parse(vpsIssuer.bytes.toString('utf8')); } catch { fail('STOP_PRE_AUTHORITY'); }
      try { transportedAttestation = JSON.parse(launchAttestationCandidate.bytes.toString('utf8')); } catch { fail('OPERATION_AUTHORITY_PUBLISHER'); }
      validateOperationAuthority(authorityRecord, launchAttestation);
      validateLaunchAttestation(transportedAttestation);
      if (!canonicalJson(transportedAttestation).equals(canonicalJson(launchAttestation))
          || request.controller_candidate_sha256 !== launchAttestation.components.controller.sha256
          || request.launcher_candidate_sha256 !== launchAttestation.components.launcher.sha256
          || request.launch_attestation_candidate_sha256 !== sha256(launchAttestationCandidate.bytes)
          || request.authority_manifest_candidate_sha256 !== launchAttestation.authority_manifest_sha256
          || request.ssh_config_candidate_sha256 !== authorityRecord.ssh.config_sha256
          || request.ssh_known_hosts_candidate_sha256 !== authorityRecord.ssh.known_hosts_sha256
          || request.ssh_private_key_candidate_sha256 !== authorityRecord.ssh.identity_sha256
          || request.ssh_public_key_candidate_sha256 !== authorityRecord.ssh.identity_public_key_sha256
          || request.ssh_trust_descriptor_candidate_sha256 !== authorityRecord.ssh.trust_descriptor_sha256) {
        fail('OPERATION_AUTHORITY_PUBLISHER');
      }
      const materializedInputs = [
        { role: 'node-runtime', path: request.node_candidate_path, sha256: request.node_candidate_sha256 },
        { role: 'controller', path: request.controller_candidate_path, sha256: request.controller_candidate_sha256 },
        { role: 'launcher-runtime', path: request.launcher_candidate_path, sha256: request.launcher_candidate_sha256 },
        { role: 'launch-attestation', path: request.launch_attestation_candidate_path, sha256: request.launch_attestation_candidate_sha256 },
        { role: 'authority-manifest', path: request.authority_manifest_candidate_path, sha256: request.authority_manifest_candidate_sha256 },
        { role: 'operation-authority', path: request.authority_candidate_path, sha256: request.authority_candidate_sha256 },
        { role: 'ssh-config', path: request.ssh_config_candidate_path, sha256: request.ssh_config_candidate_sha256 },
        { role: 'ssh-known-hosts', path: request.ssh_known_hosts_candidate_path, sha256: request.ssh_known_hosts_candidate_sha256 },
        { role: 'ssh-private-key', path: request.ssh_private_key_candidate_path, sha256: request.ssh_private_key_candidate_sha256 },
        { role: 'ssh-public-key', path: request.ssh_public_key_candidate_path, sha256: request.ssh_public_key_candidate_sha256 },
        { role: 'ssh-trust-descriptor', path: request.ssh_trust_descriptor_candidate_path, sha256: request.ssh_trust_descriptor_candidate_sha256 },
      ];
      const expectedEntries = materializedInputs.map(({ role, path: inputPath, sha256: value }) => ({
        role, path_sha256: sha256(Buffer.from(inputPath)), sha256: value,
      }));
      validatePublisherTransportManifest(inputManifest, {
        authoritySha: launchAttestation.authority_sha,
        remoteGenerationId: authorityRecord.context.generations.remote,
        controllerGenerationId: authorityRecord.context.generations.controller,
        collectorContractsSha256: sha256(canonicalJson(authorityRecord.scans)),
        entries: expectedEntries,
      });
      verifySignedVpsOperationAuthorityPass(vpsPassReceipt, vpsIssuerReceipt, {
        authoritySha: launchAttestation.authority_sha,
        authorityTree: launchAttestation.authority_tree,
        authoritySubjectSha256: launchAttestation.authority_subject_sha256,
        authorityManifestSha256: launchAttestation.authority_manifest_sha256,
        operationAuthoritySha256: request.authority_candidate_sha256,
        nodeCandidateSha256: request.node_candidate_sha256,
        collectorContractsSha256: inputManifest.collector_contracts_sha256,
        publisherInputManifestSha256: request.publisher_input_manifest_sha256,
        remoteGenerationId: authorityRecord.context.generations.remote,
        controllerGenerationId: authorityRecord.context.generations.controller,
        transferPayloadSha256: inputManifest.transfer_payload_sha256,
      });
      validatePublisherHumanAuthorizationReceipt(humanAuthorization, {
        authoritySha: launchAttestation.authority_sha,
        authorityManifestSha256: launchAttestation.authority_manifest_sha256,
        nodeBinarySha256: request.node_candidate_sha256,
        operationAuthoritySha256: request.authority_candidate_sha256,
        publisherInputManifestSha256: request.publisher_input_manifest_sha256,
        vpsOperationAuthorityPassSha256: request.vps_operation_authority_pass_sha256,
      });
      const installation = buildPublisherInstallationContract({
        authoritySha: launchAttestation.authority_sha,
        controllerGenerationId: authorityRecord.context.generations.controller,
      });
      const launcherBootstrapAuthority = buildExternalLauncherAuthority({
        authoritySha: launchAttestation.authority_sha,
        controllerGenerationId: authorityRecord.context.generations.controller,
        nodeSha256: request.node_candidate_sha256,
        controllerSha256: request.controller_candidate_sha256,
        launcherSha256: request.launcher_candidate_sha256,
        launchAttestationSha256: request.launch_attestation_candidate_sha256,
        authorityManifestSha256: request.authority_manifest_candidate_sha256,
        allowedModes: EXTERNAL_OPERATIONAL_LAUNCHER_MODES,
      });
      const expectedShaByRole = {
        'node-runtime': request.node_candidate_sha256, controller: request.controller_candidate_sha256,
        'launcher-runtime': request.launcher_candidate_sha256,
        'launcher-bootstrap-authority': sha256(launcherBootstrapAuthority),
        'launch-attestation': request.launch_attestation_candidate_sha256,
        'authority-manifest': request.authority_manifest_candidate_sha256,
        'operation-authority': request.authority_candidate_sha256,
        'human-authorization': request.human_authorization_receipt_sha256,
        'vps-pass': request.vps_operation_authority_pass_sha256,
        'vps-issuer-authority': request.vps_issuer_authority_sha256,
        'publisher-input-manifest': request.publisher_input_manifest_sha256,
        'ssh-config': request.ssh_config_candidate_sha256,
        'ssh-known-hosts': request.ssh_known_hosts_candidate_sha256,
        'ssh-private-key': request.ssh_private_key_candidate_sha256,
        'ssh-public-key': request.ssh_public_key_candidate_sha256,
        'ssh-trust-descriptor': request.ssh_trust_descriptor_candidate_sha256,
      };
      const bytesByRole = {
        'node-runtime': nodeCandidate.bytes,
        controller: controllerCandidate.bytes,
        'launcher-runtime': launcherCandidate.bytes,
        'launcher-bootstrap-authority': launcherBootstrapAuthority,
        'launch-attestation': launchAttestationCandidate.bytes,
        'authority-manifest': authorityManifestCandidate.bytes,
        'operation-authority': authorityCandidate.bytes,
        'human-authorization': humanReceipt.bytes,
        'vps-pass': vpsPass.bytes,
        'vps-issuer-authority': vpsIssuer.bytes,
        'publisher-input-manifest': publisherInputManifest.bytes,
        'ssh-config': sshCandidates['ssh-config'].bytes,
        'ssh-known-hosts': sshCandidates['ssh-known-hosts'].bytes,
        'ssh-private-key': sshCandidates['ssh-private-key'].bytes,
        'ssh-public-key': sshCandidates['ssh-public-key'].bytes,
        'ssh-trust-descriptor': sshCandidates['ssh-trust-descriptor'].bytes,
      };
      for (const [role, bytes] of Object.entries(bytesByRole)) {
        if (sha256(bytes) !== expectedShaByRole[role]) fail('OPERATION_AUTHORITY_PUBLISHER');
      }
      const receiverRoot = path.join(
        requestRoot, 'receiver', authorityRecord.context.generations.remote,
        authorityRecord.context.generations.controller, request.publisher_input_manifest_sha256,
      );
      await ensurePrivateDirectoryChain(homedir(), receiverRoot);
      for (const [role, bytes] of Object.entries(bytesByRole)) {
        await writeOnceBytes(path.join(receiverRoot, `${role}.payload`), bytes);
      }
      const sourceObservationsByRole = {};
      for (const [role, expectedSha256] of Object.entries(expectedShaByRole)) {
        const sourcePath = path.join(receiverRoot, `${role}.payload`);
        const observed = await readBoundLocalFile(sourcePath, {
          code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256, modes: [0o600],
        });
        sourceObservationsByRole[role] = {
          role, path: sourcePath, path_sha256: sha256(Buffer.from(sourcePath)),
          sha256: sha256(observed.bytes), ...observed.metadata,
          identity_sha256: physicalIdentitySha256(observed.metadata),
        };
      }
      const publisher1Request = buildPublisher1TransactionRequest({
        context: authorityRecord.context,
        receiverRoot,
        receiverManifestSha256: request.publisher_input_manifest_sha256,
        shaByRole: expectedShaByRole,
        sourceObservationsByRole,
      });
      const publisher1RequestBytes = canonicalJson(publisher1Request);
      const publisher1RequestPath = path.join(requestRoot, 'publisher1-transaction.request.json');
      await writeOnceBytes(publisher1RequestPath, publisher1RequestBytes);
      const requestObservation = await readBoundLocalFile(publisher1RequestPath, {
        code: 'OPERATION_AUTHORITY_PUBLISHER', expectedSha256: sha256(publisher1RequestBytes), modes: [0o600],
      });
      const receiverStat = await lstat(receiverRoot, { bigint: true });
      if (!receiverStat.isDirectory() || receiverStat.isSymbolicLink()
          || receiverStat.uid !== BigInt(process.getuid()) || receiverStat.gid !== BigInt(process.getgid())
          || (receiverStat.mode & 0o777n) !== 0o700n) fail('OPERATION_AUTHORITY_PUBLISHER');
      const receiverPhysical = metadataFromBigIntStat(receiverStat, 'OPERATION_AUTHORITY_PUBLISHER');
      const receiverMetadata = receiverPhysical.metadata;
      const requestIdentitySha256 = physicalIdentitySha256(requestObservation.metadata);
      const receiverRootIdentitySha256 = receiverPhysical.identity_sha256;
      const materializer = await readPublisher1MaterializerAuthority(authorityRecord.context);
      if (materializer.authority.issuer_authority_sha256 !== request.vps_issuer_authority_sha256) fail('STOP_PRE_AUTHORITY');
      validatePublisher1MaterializerAuthorityBinding({
        schema_version: materializer.authority.schema_version, purpose: materializer.authority.purpose,
        authority_sha: materializer.authority.authority_sha,
        controller_generation_id: materializer.authority.controller_generation_id,
        request_path_sha256: materializer.authority.request_path_sha256,
        request_sha256: materializer.authority.request_sha256,
        request_identity_sha256: materializer.authority.request_identity_sha256,
        request_uid: materializer.authority.request_uid, request_gid: materializer.authority.request_gid,
        request_mode: materializer.authority.request_mode, request_nlink: materializer.authority.request_nlink,
        receiver_root_path_sha256: materializer.authority.receiver_root_path_sha256,
        receiver_root_identity_sha256: materializer.authority.receiver_root_identity_sha256,
        receiver_leaves: materializer.authority.receiver_leaves,
        normal_executor_authorized: materializer.authority.normal_executor_authorized,
        raw_values: materializer.authority.raw_values,
      }, {
        authoritySha: authorityRecord.context.authority.commit,
        controllerGenerationId: authorityRecord.context.generations.controller,
        requestPath: publisher1RequestPath, requestSha256: sha256(publisher1RequestBytes),
        requestIdentitySha256, requestUid: requestObservation.metadata.uid,
        requestGid: requestObservation.metadata.gid, receiverRoot, receiverRootIdentitySha256,
        receiverLeaves: publisher1Request.entries.map((entry) => ({
          role: entry.role, path_sha256: entry.source_path_sha256, sha256: entry.source_sha256,
          uid: entry.source_uid, gid: entry.source_gid, mode: entry.source_mode,
          nlink: entry.source_nlink, size: entry.source_size, mtime_ns: entry.source_mtime_ns,
          dev: entry.source_dev, ino: entry.source_ino,
          identity_sha256: entry.source_identity_sha256,
        })),
      });
      const commands = [
        'set -eu', 'umask 077',
        `PUBLISHER1_RESULT="$(${shellQuote(materializer.binaryPath)} --publisher1-transaction ${shellQuote(publisher1RequestPath)} ${shellQuote(sha256(publisher1RequestBytes))})"`,
        "case \"$PUBLISHER1_RESULT\" in 'PUBLISHER1_TRANSACTION PASS status=CREATED effect_executions=1'|'PUBLISHER1_TRANSACTION PASS status=EXISTS_VERIFIED effect_executions=0'|'PUBLISHER1_TRANSACTION PASS status=EXISTS_RECOVERED effect_executions=0') ;; *) exit 1 ;; esac",
        "printf 'OPERATION_AUTHORITY_PUBLISHER PASS\\n'",
      ];
      const stateRoot = publisher1Request.state_root;
      const versionRoot = installation.version_root;
      const expected = {
        authority_sha: authorityRecord.context.authority.commit,
        controller_generation_id: authorityRecord.context.generations.controller,
        request_sha256: sha256(publisher1RequestBytes),
        receiver_root_sha256: sha256(Buffer.from(receiverRoot)),
      };
      const observe = async () => {
        const claimPath = path.join(stateRoot, 'publisher1.claim.json');
        const resultPath = path.join(stateRoot, 'publisher1.result.json');
        const [claimStat, resultStat, versionStat] = await Promise.all([
          lstat(claimPath).catch(() => null), lstat(resultPath).catch(() => null), lstat(versionRoot).catch(() => null),
        ]);
        if (!claimStat && !resultStat && !versionStat) return { state: 'ABSENT' };
        if (!claimStat || !resultStat || !versionStat) return { state: 'PARTIAL' };
        const claimObserved = await readRootImmutableFile(claimPath, null, 0o444, 'PUBLISHER1_RECOVERY_STOP');
        const resultObserved = await readRootImmutableFile(resultPath, null, 0o444, 'PUBLISHER1_RECOVERY_STOP');
        let claimRecord;
        let resultRecord;
        try {
          claimRecord = JSON.parse(claimObserved.bytes.toString('utf8'));
          resultRecord = JSON.parse(resultObserved.bytes.toString('utf8'));
        } catch { fail('PUBLISHER1_RECOVERY_STOP'); }
        const expectedClaim = {
          schema_version: 1, purpose: 'CI3_PUBLISHER1_TRANSACTION_CLAIM_V1',
          authority_sha: expected.authority_sha,
          remote_generation_id: authorityRecord.context.generations.remote,
          controller_generation_id: expected.controller_generation_id,
          receiver_manifest_sha256: request.publisher_input_manifest_sha256,
          request_sha256: expected.request_sha256,
          request_path_sha256: sha256(Buffer.from(publisher1RequestPath)),
          request_identity_sha256: requestIdentitySha256,
          receiver_root_path_sha256: expected.receiver_root_sha256,
          receiver_root_identity_sha256: receiverRootIdentitySha256,
          entries: publisher1Request.entries.map((entry) => ({
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
        if (!canonicalJson(claimRecord).equals(canonicalJson(expectedClaim))
            || resultRecord?.purpose !== 'CI3_PUBLISHER1_TRANSACTION_RESULT_V1'
            || resultRecord.authority_sha !== expected.authority_sha
            || resultRecord.controller_generation_id !== expected.controller_generation_id
            || resultRecord.claim_sha256 !== sha256(claimObserved.bytes)
            || resultRecord.request_sha256 !== expected.request_sha256
            || resultRecord.terminal_state !== 'PUBLISHED' || resultRecord.raw_values !== false
            || !Array.isArray(resultRecord.observations)
            || resultRecord.observations.length !== publisher1Request.entries.length
            || !canonicalJson(resultRecord.source_observations).equals(canonicalJson(
              expectedClaim.entries.map((entry) => ({
                role: entry.role, source_path_sha256: entry.source_path_sha256,
                source_sha256: entry.sha256, source_uid: entry.source_uid, source_gid: entry.source_gid,
                source_mode: entry.source_mode, source_nlink: entry.source_nlink,
                source_size: entry.source_size, source_mtime_ns: entry.source_mtime_ns,
                source_dev: entry.source_dev, source_ino: entry.source_ino,
                source_identity_sha256: entry.source_identity_sha256,
              })),
            ))) fail('PUBLISHER1_RECOVERY_STOP');
        await verifyInstalledPublisherTargets({
          expectedSha256ByRole: expectedShaByRole,
          readTarget: async (role) => {
            const target = installation.targets[role];
            const observed = await readRootImmutableFile(target.path, expectedShaByRole[role], target.mode, 'PUBLISHER1_RECOVERY_STOP');
            return { bytes: observed.bytes, metadata: observed.metadata, immutable: true };
          },
        });
        return {
          state: 'SETTLED', ...expected, claim_sha256: sha256(claimObserved.bytes),
          result_sha256: sha256(resultObserved.bytes), tree_verified: true, raw_values: false,
        };
      };
      return runPublisher1ControllerTransaction({
        expected, observe,
        invokeAdmin: async () => runAdminPublisher(commands.join('\n'), 'OPERATION_AUTHORITY_PUBLISHER'),
        persistReceipt: async (settled) => writeOnceJson(
          path.join(requestRoot, 'publisher1-controller.settlement.json'),
          {
            schema_version: 1, purpose: 'CI3_PUBLISHER1_CONTROLLER_SETTLEMENT_V1',
            authority_sha: settled.authority_sha,
            controller_generation_id: settled.controller_generation_id,
            request_sha256: settled.request_sha256, receiver_root_sha256: settled.receiver_root_sha256,
            claim_sha256: settled.claim_sha256, result_sha256: settled.result_sha256,
            tree_verified: true, raw_values: false,
          },
        ),
      });
    },
  };
}

function syntheticContext() {
  const component = (name, character) => ({ path: COMPONENT_PATHS[name], blob_oid: character.repeat(40), sha256: character.repeat(64) });
  return {
    authority: {
      commit: 'a'.repeat(40), parent: AUTHORITY_PARENT, tree: 'b'.repeat(40), subject: AUTHORITY_SUBJECT,
      manifest_sha256: 'c'.repeat(64),
      components: { generator: component('generator', '1'), controller: component('controller', '2'), launcher: component('launcher', '3'), writer: component('writer', '4') },
    },
    generations: {
      remote: `remote-${'b'.repeat(64)}`, controller: `controller-${'c'.repeat(64)}`,
      simulator: `simulator-${'d'.repeat(64)}`, terminal: `terminal-${'e'.repeat(64)}`,
    },
    remote: {
      bundle_path_sha256: '2'.repeat(64), receipt_path_sha256: '3'.repeat(64), receipt_sha256: '4'.repeat(64),
      config_path_sha256: '5'.repeat(64), config_sha256: '6'.repeat(64), credential_path_sha256: '7'.repeat(64), credential_sha256: '8'.repeat(64),
    },
  };
}

function syntheticSimulatorReceipt(context) {
  return {
    schema_version: 1, purpose: 'CI3_SIMULATOR_GATE_RECEIPT_V2', authority_sha: context.authority.commit,
    controller_generation_id: context.generations.controller, simulator_generation_id: context.generations.simulator,
    device_selection_sha256: '1'.repeat(64), runtime_sha256: '2'.repeat(64), app_installation_sha256: '3'.repeat(64),
    source_commit: CI3_PARENT, bundle_id: BUNDLE_ID, container_identity_sha256: '4'.repeat(64), probe_config_sha256: '5'.repeat(64),
    probe_credential_sha256: '6'.repeat(64), probe_ack_sha256: '7'.repeat(64), removal_proof_sha256: '8'.repeat(64),
    phases: [...SIMULATOR_PHASES], phase_receipt_hashes: SIMULATOR_PHASES.map((_, index) => String((index % 8) + 1).repeat(64)),
    attempts: { select: 1, resolve: 1, install: 1, launch: 1, ack: 1, remove: 1, reobserve: 1 },
    raw_container_path_reported: false, terminal_state: 'SIMULATOR_GATE_PASS',
  };
}

function syntheticScanReceipt(scanId, context) {
  return {
    schema_version: 1, purpose: 'CI3_TERMINAL_SCAN_RECEIPT_V1', scan_id: scanId,
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    remote_generation_id: context.generations.remote, local_bundle_sha256: '1'.repeat(64), simulator_install_sha256: '2'.repeat(64),
    simulator_generation_id: context.generations.simulator, terminal_generation_id: context.generations.terminal,
    worktree_diff_sha256: '3'.repeat(64), input_manifest_sha256: '4'.repeat(64), tool_sha256: '5'.repeat(64), command_sha256: '6'.repeat(64), scanner_schema_sha256: scannerSchemaSha256(scanId),
    counters: { secret: 0, pii: 0, jwt: 0, token: 0, raw_destination: 0 },
    input_observations: [{ path: `/synthetic/${scanId}`, path_sha256: sha256(Buffer.from(`/synthetic/${scanId}`)), sha256: '9'.repeat(64), metadata: { dev: '1', gid: 0, ino: '2', mode: 0o600, mtime_ns: '3', nlink: 1, size: 1, uid: 0 } }],
    started_at: '2026-08-30T12:00:00.000Z', finished_at: '2026-08-30T12:00:01.000Z', result: 'CLEAN', match_count: 0,
    output_sha256: '7'.repeat(64), redaction: true, input_stable_after_scan: true,
  };
}

export async function runSyntheticProtocol({ scenarioId = null, scenarioSha256 = null } = {}) {
  const context = syntheticContext();
  const scenario = scenarioId === null && scenarioSha256 === null
    ? null
    : FULL_PROTOCOL_E2E_SCENARIOS.find(({ id }) => id === scenarioId);
  if ((scenarioId === null) !== (scenarioSha256 === null)
      || (scenarioId !== null && (!scenario || sha256(Buffer.from(scenarioId)) !== scenarioSha256))) fail('SELF_TEST_SCENARIO');
  const externalRestart = process.env.CI3_SYNTHETIC_EXTERNAL_RESTART === '1' && scenario !== null;
  const physicalRoot = externalRestart
    ? path.join(await realpath(process.env.CI3_SYNTHETIC_E2E_ROOT), scenarioSha256, 'protocol-state')
    : await mkdtemp(path.join(tmpdir(), 'ci3-controller-self-test-'));
  if (externalRestart) await mkdir(physicalRoot, { recursive: true, mode: 0o700 });
  const durableStatePath = path.join(physicalRoot, 'journal-snapshot.json');
  let snapshot = null;
  if (externalRestart) {
    try { snapshot = JSON.parse(await readFile(durableStatePath, 'utf8')); } catch (error) { if (error?.code !== 'ENOENT') throw error; }
  }
  const mapFrom = (field) => new Map(snapshot?.[field] ?? []);
  const records = snapshot?.records ?? [];
  const events = mapFrom('events');
  const claims = mapFrom('claims');
  const results = mapFrom('results');
  const scenarioTrace = snapshot?.scenario_trace ?? [];
  let scenarioCrashArmed = scenario !== null && snapshot === null;
  let crashObserved = snapshot?.crash_observed ?? false;
  const phaseClaims = mapFrom('phase_claims');
  const phaseReceipts = mapFrom('phase_receipts');
  const phaseResults = mapFrom('phase_results');
  const phaseProduced = mapFrom('phase_produced');
  const phaseEffectRunners = new Map();
  const phaseEffectCounts = mapFrom('phase_effect_counts');
  const phasePaths = mapFrom('phase_paths');
  const persistState = async () => {
    if (!externalRestart) return;
    const state = {
      records, events: [...events], claims: [...claims], results: [...results],
      scenario_trace: scenarioTrace, crash_observed: crashObserved,
      phase_claims: [...phaseClaims], phase_receipts: [...phaseReceipts],
      phase_results: [...phaseResults], phase_produced: [...phaseProduced],
      phase_effect_counts: [...phaseEffectCounts], phase_paths: [...phasePaths],
    };
    await writeFile(durableStatePath, canonicalJson(state), { mode: 0o600 });
  };
  const markScenario = async (phase, boundary) => {
    if (scenario?.phase !== phase) return;
    scenarioTrace.push(boundary);
    if (scenarioCrashArmed && scenario.boundary === boundary) {
      scenarioCrashArmed = false;
      crashObserved = true;
      await persistState();
      const error = new Error(`SYNTHETIC_CRASH:${scenario.id}`);
      error.code = 'SYNTHETIC_CRASH';
      throw error;
    }
  };
  const journal = {
    load: async (event) => structuredClone(events.get(event) ?? null),
    append: async (record) => {
      records.push(record);
      events.set(record.event, structuredClone(record));
      await persistState();
      if (DURABLE_PHASES.includes(record.event)) await markScenario(record.event, 'after-event');
      return sha256(canonicalJson(record));
    },
    loadClaim: async (kind) => structuredClone(claims.get(kind) ?? null),
    appendClaim: async (record) => {
      records.push(record);
      const kind = record.purpose === 'CI3_MAC_BRIDGE_BOOTSTRAP_CLAIM_V1' ? 'bootstrap' : record.kind;
      claims.set(kind, structuredClone(record));
      await persistState();
      return sha256(canonicalJson(record));
    },
    loadResult: async (kind) => structuredClone(results.get(kind) ?? null),
    appendResult: async (record) => {
      records.push(record);
      if (record.kind) results.set(record.kind, structuredClone(record));
      await persistState();
      return sha256(canonicalJson(record));
    },
    appendPhaseClaim: async (record) => {
      records.push(record); phaseClaims.set(record.phase, structuredClone(record));
      await persistState();
      await markScenario(record.phase, 'after-claim'); return sha256(canonicalJson(record));
    },
    loadPhaseClaim: async (phase) => structuredClone(phaseClaims.get(phase) ?? null),
    settlePhaseReceipt: async (phase, claimSha256, result, observation) => {
      const receipt = {
        result, observation, receiptSha256: sha256(canonicalJson({ claim_sha256: claimSha256, observation, result })),
        physicalObservationSha256: observation.observation_sha256,
      };
      phaseReceipts.set(phase, structuredClone(receipt));
      await persistState();
      await markScenario(phase, 'after-receipt');
      return receipt;
    },
    reobservePhaseReceipt: async (phase) => structuredClone(phaseReceipts.get(phase) ?? null),
    appendPhaseResult: async (record) => {
      records.push(record); phaseResults.set(record.phase, structuredClone(record));
      await persistState();
      await markScenario(record.phase, 'after-result'); return sha256(canonicalJson(record));
    },
    loadPhaseResult: async (phase) => structuredClone(phaseResults.get(phase) ?? null),
  };
  const sshProvenance = {
    executable_sha256: '9'.repeat(64), code_signature_sha256: 'a'.repeat(64), effective_config_sha256: 'b'.repeat(64), trust_descriptor_sha256: 'c'.repeat(64),
  };
  const effect = (phase, operation) => {
    const runner = async (...args) => {
      phaseEffectCounts.set(phase, (phaseEffectCounts.get(phase) ?? 0) + 1);
      if (phaseEffectCounts.get(phase) !== 1) fail('SELF_TEST_REEXECUTION');
      const result = await operation(...args);
      const filePath = path.join(physicalRoot, `${phase}.effect.json`);
      await writeFile(filePath, canonicalJson({ phase, result, synthetic_only: true }), { flag: 'wx', mode: 0o600 });
      phasePaths.set(phase, { filePath, gid: (await lstat(filePath)).gid, modes: [0o600] });
      phaseProduced.set(phase, structuredClone(result));
      await persistState();
      await markScenario(phase, 'after-effect');
      return result;
    };
    phaseEffectRunners.set(phase, runner);
    return runner;
  };
  const adapters = {
    preflightPhase: async ({ event }) => markScenario(event, 'before-claim'),
    finalizeTerminalEvidence: async () => undefined,
    observePhase: async ({ event }) => {
      const physicalTarget = phasePaths.get(event);
      if (!physicalTarget) fail('PHASE_PHYSICAL_OBSERVATION');
      const { filePath, gid, modes } = physicalTarget;
      const bytes = await readFile(filePath);
      return observePhysicalEffect({
        phase: event,
        targets: [{
          role: `synthetic-${event.toLowerCase().replaceAll('_', '-')}`, path: filePath,
          state: 'PRESENT', expectedSha256: sha256(bytes), allowedGids: [gid], modes,
        }],
      });
    },
    verifyAuthority: effect('VERIFY_AUTHORITY', async () => ({ verified: true })),
    verifyWorktree: effect('VERIFY_WORKTREE', async () => ({ verified: true })),
    verifySimulator: effect('VERIFY_SIMULATOR', async () => ({ receipt: syntheticSimulatorReceipt(context) })),
    verifySsh: effect('VERIFY_SSH', async () => ({ provenance: sshProvenance })),
    readRemote: async ({ kind }) => ({ captureSha256: sha256(Buffer.from(kind)), captureIdentitySha256: sha256(Buffer.from(`identity-${kind}`)), remoteCommandSha256: sha256(Buffer.from(`command-${kind}`)), descriptorRead: true, bytes: kind.length, exit: 0, stderrClass: 'EMPTY', startedAt: '2026-08-30T12:00:00.000Z', finishedAt: '2026-08-30T12:00:01.000Z' }),
    publishLocal: effect('PUBLISH_LOCAL', async () => ({ local_bundle_sha256: '1'.repeat(64) })),
    installSimulator: effect('INSTALL_SIMULATOR', async () => ({ install_receipt_sha256: '2'.repeat(64) })),
    removeSimulatorCredential: effect('REMOVE_CREDENTIAL', async () => ({ removed: true })),
    scan: effect('RUN_SCANS', async () => TERMINAL_SCAN_IDS.map((scanId) => syntheticScanReceipt(scanId, context))),
    invokeWriter: async () => {
      const terminalScenario = scenario && TERMINAL_SETTLEMENT_PHASES.includes(scenario.phase);
      const countedPhase = terminalScenario ? scenario.phase : 'INVOKE_WRITER';
      const priorCount = phaseEffectCounts.get(countedPhase) ?? 0;
      if (priorCount === 0) {
        phaseEffectCounts.set(countedPhase, 1);
        await persistState();
      } else if (priorCount !== 1) {
        fail('SELF_TEST_REEXECUTION');
      }
      const result = process.env.CI3_SYNTHETIC_E2E_ROOT
        ? await executeSyntheticWriterEffect(context)
        : ({
        pre_anchor_sha256: '3'.repeat(64), terminal_state: 'TERMINAL_PASS',
        marker_sha256: '9'.repeat(64), marker_verified: true,
        complete_sha256: '8'.repeat(64),
        settlement: buildTerminalSettlementReceipt({
          authoritySha: context.authority.commit, generations: context.generations,
          preAnchorSha256: '3'.repeat(64),
          invokeWriter: { claim_sha256: '1'.repeat(64), receipt_sha256: '2'.repeat(64), result_sha256: '3'.repeat(64) },
          verifyAnchor: { claim_sha256: '4'.repeat(64), receipt_sha256: '5'.repeat(64), result_sha256: '6'.repeat(64) },
          settlementAuthoritySha256: '4'.repeat(64),
          terminalSettlementContractsSha256: '5'.repeat(64),
          terminalPhaseGraphSha256: '6'.repeat(64),
          terminalFinalScanSha256: '7'.repeat(64),
        }),
      });
      if (externalRestart && snapshot && terminalScenario) {
        crashObserved = true;
        if (!scenarioTrace.includes(scenario.boundary)) scenarioTrace.push(scenario.boundary);
      }
      return result;
    },
    verifyAnchor: effect('VERIFY_ANCHOR', async ({ writer }) => {
      if (!process.env.CI3_SYNTHETIC_E2E_ROOT) return { verified: true };
      const descriptor = await readSyntheticWriterDescriptor(context);
      const preAnchorBytes = await readFile(descriptor.anchor_path);
      const settlementPath = path.join(descriptor.anchor_root, descriptor.authority,
        descriptor.generations.terminal, 'terminal-settlement.json');
      const settlementBytes = await readFile(settlementPath);
      const finalScanBytes = await readFile(path.join(descriptor.anchor_root, descriptor.authority,
        descriptor.generations.terminal, 'terminal-final-scan.json'));
      const completeBytes = await readFile(path.join(descriptor.anchor_root, descriptor.authority,
        descriptor.generations.terminal, 'complete-result.json'));
      const completeFinalScanBytes = await readFile(path.join(descriptor.anchor_root, descriptor.authority,
        descriptor.generations.terminal, 'complete-final-scan.json'));
      if (sha256(preAnchorBytes) !== writer.pre_anchor_sha256
          || JSON.parse(settlementBytes).settlement_sha256 !== writer.settlement.settlement_sha256
          || sha256(completeBytes) !== writer.complete_sha256) fail('SELF_TEST_E2E');
      validateTerminalCompleteResult(JSON.parse(completeBytes), { settlementBytes, finalScanBytes });
      validateTerminalCompleteFinalScan(JSON.parse(completeFinalScanBytes), completeBytes);
      return { verified: true, pre_anchor_sha256: writer.pre_anchor_sha256 };
    }),
    recoverPhase: async ({ event, claim }) => {
      if (!phaseProduced.has(event)) fail('CLAIM_CONSUMED_NO_RESULT');
      const result = structuredClone(phaseProduced.get(event));
      const observation = await adapters.observePhase({ event, result, context, recovery: true });
      const receipt = {
        result,
        observation,
        receiptSha256: sha256(canonicalJson({ claim_sha256: sha256(canonicalJson(claim)), observation, result })),
        physicalObservationSha256: observation.observation_sha256,
      };
      phaseReceipts.set(event, structuredClone(receipt));
      return receipt;
    },
    recoverRemote: async ({ kind }) => ({ captureSha256: sha256(Buffer.from(kind)), captureIdentitySha256: sha256(Buffer.from(`identity-${kind}`)), remoteCommandSha256: sha256(Buffer.from(`command-${kind}`)), descriptorRead: true, bytes: kind.length, exit: 0, stderrClass: 'EMPTY', startedAt: '2026-08-30T12:00:00.000Z', finishedAt: '2026-08-30T12:00:01.000Z' }),
    settleTerminal: async ({ writer, invokeWriter, verifyAnchor }) => writer?.settlement ?? buildTerminalSettlementReceipt({
      authoritySha: context.authority.commit, generations: context.generations,
      preAnchorSha256: '3'.repeat(64), invokeWriter, verifyAnchor,
      settlementAuthoritySha256: '4'.repeat(64),
      terminalSettlementContractsSha256: '5'.repeat(64),
      terminalPhaseGraphSha256: '6'.repeat(64),
      terminalFinalScanSha256: '7'.repeat(64),
    }),
  };
  try {
    let outcome;
    try {
      outcome = await runProtocol({ adapters, context, journal });
    } catch (error) {
      if (externalRestart && snapshot && scenario?.boundary === 'after-claim'
          && error?.code === 'CLAIM_CONSUMED_NO_RESULT') {
        outcome = { state: 'STOP_CLAIM_CONSUMED_NO_RESULT', scans: [], settlement: null };
      } else {
      if (!scenario || error?.code !== 'SYNTHETIC_CRASH') throw error;
      if (externalRestart) throw error;
      try {
        outcome = await runProtocol({ adapters, context, journal });
      } catch (recoveryError) {
        if (scenario.boundary !== 'after-claim' || recoveryError?.code !== 'CLAIM_CONSUMED_NO_RESULT') throw recoveryError;
        outcome = { state: 'STOP_CLAIM_CONSUMED_NO_RESULT', scans: [], settlement: null };
      }
      }
    }
    if (scenario) {
      const expectedEffectCount = scenario.boundary === 'after-claim'
        && !TERMINAL_SETTLEMENT_PHASES.includes(scenario.phase) ? 0 : 1;
      if (!crashObserved || !scenarioTrace.includes(scenario.boundary)
          || (phaseEffectCounts.get(scenario.phase) ?? 0) !== expectedEffectCount) fail('SELF_TEST_SCENARIO');
    }
    const phaseTriples = Object.fromEntries(['INVOKE_WRITER', 'VERIFY_ANCHOR'].map((phase) => [phase, {
      claim: structuredClone(phaseClaims.get(phase)),
      receipt: structuredClone(phaseReceipts.get(phase)),
      result: structuredClone(phaseResults.get(phase)),
    }]));
    return {
      ...outcome,
      scan_ids: outcome.scans.map(({ scan_id: scanId }) => scanId),
      network_calls: 0,
      privilege_prompts: 0,
      journal_records: records.length,
      crash_observed: crashObserved,
      recovery_resumed: scenario ? true : false,
      effect_count_at_most_one: [...phaseEffectCounts.values()].every((count) => count <= 1),
      authority_sha: context.authority.commit,
      generations: structuredClone(context.generations),
      phase_triples: phaseTriples,
    };
  } finally {
    if (!externalRestart) await rm(physicalRoot, { recursive: true, force: true });
  }
}

async function readSyntheticWriterDescriptor(context) {
  const code = 'SELF_TEST_E2E';
  const descriptorPath = process.env.CI3_SYNTHETIC_WRITER_FIXTURE;
  if (!path.isAbsolute(descriptorPath ?? '') || descriptorPath.includes('/../')) fail(code);
  let descriptor;
  try { descriptor = JSON.parse(await readFile(descriptorPath, 'utf8')); } catch { fail(code); }
  exactKeys(descriptor, [
    'anchor_path', 'anchor_root', 'authority', 'authority_receipt_path', 'evidence_root',
    'generations', 'manifest_path', 'protocol_state_path_sha256', 'protocol_state_sha256',
    'purpose', 'raw_values', 'root', 'schema_version',
  ], code);
  if (descriptor.schema_version !== 1 || descriptor.purpose !== 'CI3_SYNTHETIC_WRITER_FIXTURE_V1'
      || descriptor.raw_values !== false || descriptor.authority !== context.authority.commit
      || !canonicalJson(descriptor.generations).equals(canonicalJson(context.generations))) fail(code);
  requireSha(descriptor.protocol_state_path_sha256, code);
  requireSha(descriptor.protocol_state_sha256, code);
  const protocolStatePath = path.join(descriptor.evidence_root, 'controller-durable-state-root.json');
  let protocolStateBytes;
  let protocolState;
  try {
    protocolStateBytes = await readFile(protocolStatePath);
    protocolState = JSON.parse(protocolStateBytes);
  } catch { fail(code); }
  const scenarioId = process.env.CI3_SYNTHETIC_E2E_SCENARIO;
  const scenarioSha256 = process.env.CI3_SYNTHETIC_SCENARIO_SHA256;
  const durableStatePath = path.join(await realpath(process.env.CI3_SYNTHETIC_E2E_ROOT), scenarioSha256,
    'protocol-state', 'journal-snapshot.json');
  if (descriptor.protocol_state_path_sha256 !== sha256(Buffer.from(durableStatePath))
      || descriptor.protocol_state_sha256 !== sha256(protocolStateBytes)
      || protocolState.schema_version !== 1
      || protocolState.purpose !== 'CI3_SYNTHETIC_DURABLE_PROTOCOL_STATE_V1'
      || protocolState.scenario_id !== scenarioId
      || protocolState.scenario_sha256 !== scenarioSha256
      || protocolState.snapshot_path_sha256 !== sha256(Buffer.from(durableStatePath))
      || protocolState.snapshot_sha256 !== sha256(canonicalJson(protocolState.snapshot))
      || protocolState.raw_values !== false) fail(code);
  return descriptor;
}

async function materializeSyntheticWriterFixture() {
  const code = 'SELF_TEST_E2E';
  const descriptorPath = process.env.CI3_SYNTHETIC_WRITER_FIXTURE;
  try {
    await readFile(descriptorPath);
    return;
  } catch (error) {
    if (error?.code !== 'ENOENT') fail(code);
  }
  const materializer = process.env.CI3_SYNTHETIC_WRITER_MATERIALIZER;
  const e2eRoot = process.env.CI3_SYNTHETIC_E2E_ROOT;
  const scenarioId = process.env.CI3_SYNTHETIC_E2E_SCENARIO;
  const scenarioSha256 = process.env.CI3_SYNTHETIC_SCENARIO_SHA256;
  const writerBinary = process.env.CI3_SYNTHETIC_WRITER_BINARY;
  const writerSha256 = process.env.CI3_SYNTHETIC_WRITER_SHA256;
  if (!path.isAbsolute(materializer ?? '') || materializer.includes('/../')
      || !path.isAbsolute(e2eRoot ?? '') || e2eRoot.includes('/../')
      || !path.isAbsolute(descriptorPath ?? '') || descriptorPath.includes('/../')
      || !path.isAbsolute(writerBinary ?? '') || writerBinary.includes('/../')
      || !FULL_PROTOCOL_E2E_SCENARIOS.some(({ id }) => id === scenarioId)
      || sha256(Buffer.from(scenarioId ?? '')) !== scenarioSha256) fail(code);
  requireSha(writerSha256, code);
  const durableStatePath = path.join(await realpath(e2eRoot), scenarioSha256,
    'protocol-state', 'journal-snapshot.json');
  const beforeBytes = await readFile(durableStatePath);
  let parsed;
  try { parsed = JSON.parse(beforeBytes); } catch { fail(code); }
  if (!Array.isArray(parsed.records) || !Array.isArray(parsed.phase_results)) fail(code);
  const materialized = spawnSync(process.execPath, [materializer, '--materialize-synthetic-fixture'], {
    encoding: 'utf8',
    env: {
      ...CLOSED_BOOTSTRAP_ENVIRONMENT,
      CI3_SYNTHETIC_WRITER_BINARY: writerBinary,
      CI3_SYNTHETIC_WRITER_SHA256: writerSha256,
      CI3_SYNTHETIC_FIXTURE_DESCRIPTOR: descriptorPath,
      CI3_SYNTHETIC_FIXTURE_PARENT: e2eRoot,
      CI3_SYNTHETIC_PROTOCOL_STATE_PATH: durableStatePath,
      CI3_SYNTHETIC_E2E_SCENARIO: scenarioId,
      CI3_SYNTHETIC_SCENARIO_SHA256: scenarioSha256,
    },
    timeout: 60000,
  });
  const afterBytes = await readFile(durableStatePath);
  if (materialized.status !== 0 || materialized.signal !== null
      || materialized.stdout !== '' || materialized.stderr !== ''
      || !beforeBytes.equals(afterBytes)) fail(code);
}

async function executeSyntheticWriterEffect(context) {
  const code = 'SELF_TEST_E2E';
  const writerBinary = process.env.CI3_SYNTHETIC_WRITER_BINARY;
  const writerExpectedSha256 = process.env.CI3_SYNTHETIC_WRITER_SHA256;
  if (!path.isAbsolute(writerBinary ?? '') || writerBinary.includes('/../')) fail(code);
  requireSha(writerExpectedSha256, code);
  if (sha256(await readFile(writerBinary)) !== writerExpectedSha256) fail(code);
  await materializeSyntheticWriterFixture();
  const descriptor = await readSyntheticWriterDescriptor(context);
  const generationArguments = [
    descriptor.generations.remote, descriptor.generations.controller,
    descriptor.generations.simulator, descriptor.generations.terminal,
  ];
  const written = spawnSync(writerBinary, [
    '--write', descriptor.manifest_path, descriptor.authority_receipt_path,
    descriptor.authority, ...generationArguments,
  ], {
    encoding: 'utf8', env: {
      ...CLOSED_BOOTSTRAP_ENVIRONMENT,
      CI3_SYNTHETIC_ANCHOR_ROOT: descriptor.anchor_root,
      CI3_SYNTHETIC_E2E_SCENARIO: process.env.CI3_SYNTHETIC_E2E_SCENARIO,
      CI3_SYNTHETIC_SCENARIO_SHA256: process.env.CI3_SYNTHETIC_SCENARIO_SHA256,
    }, timeout: 60000,
  });
  if (written.status !== 0 && written.signal === null && written.stdout === ''
      && written.stderr === 'ERROR SYNTHETIC_CRASH\n') {
    const error = new Error(`SYNTHETIC_CRASH:${process.env.CI3_SYNTHETIC_E2E_SCENARIO}`);
    error.code = 'SYNTHETIC_CRASH';
    throw error;
  }
  const match = written.stdout?.trim().match(/^WRITER_TRANSACTION PASS status=(?:CREATED|EXISTS_VERIFIED) pre_anchor_sha256=([a-f0-9]{64}) settlement_sha256=([a-f0-9]{64})$/);
  if (written.status !== 0 || written.signal !== null || written.stderr !== '' || !match) fail(code);
  const settlementPath = path.join(descriptor.anchor_root, descriptor.authority,
    descriptor.generations.terminal, 'terminal-settlement.json');
  const settlementBytes = await readFile(settlementPath);
  const finalScanBytes = await readFile(path.join(descriptor.anchor_root, descriptor.authority,
    descriptor.generations.terminal, 'terminal-final-scan.json'));
  const completeBytes = await readFile(path.join(descriptor.anchor_root, descriptor.authority,
    descriptor.generations.terminal, 'complete-result.json'));
  const completeFinalScanBytes = await readFile(path.join(descriptor.anchor_root, descriptor.authority,
    descriptor.generations.terminal, 'complete-final-scan.json'));
  const markerBytes = await readFile(path.join(descriptor.anchor_root, descriptor.authority,
    descriptor.generations.terminal, 'terminal-pass.marker.json'));
  let settlement;
  let complete;
  let marker;
  try {
    settlement = JSON.parse(settlementBytes);
    complete = JSON.parse(completeBytes);
    marker = JSON.parse(markerBytes);
  } catch { fail(code); }
  validateTerminalSettlementReceipt(settlement);
  validateTerminalCompleteResult(complete, { settlementBytes, finalScanBytes });
  validateTerminalCompleteFinalScan(JSON.parse(completeFinalScanBytes), completeBytes);
  if (settlement.settlement_sha256 !== match[2] || settlement.pre_anchor_sha256 !== match[1]
      || marker?.purpose !== 'CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1'
      || marker?.authority_sha !== context.authority.commit
      || !canonicalJson(marker?.generations).equals(canonicalJson(context.generations))
      || marker?.terminal_state !== 'TERMINAL_PASS'
      || marker?.receipt_is_commit_marker !== true
      || marker?.normal_executor_authorized !== false) fail(code);
  return {
    pre_anchor_sha256: match[1], settlement, complete_sha256: sha256(completeBytes),
    marker_sha256: sha256(markerBytes), marker_verified: true,
    terminal_state: 'TERMINAL_PASS',
  };
}

async function runSyntheticIntegratedE2E({ scenarioId, scenarioSha256, outcome }) {
  const code = 'SELF_TEST_E2E';
  const e2eRoot = process.env.CI3_SYNTHETIC_E2E_ROOT;
  if (!path.isAbsolute(e2eRoot ?? '') || e2eRoot.includes('/../')) fail(code);
  if (outcome.state === 'STOP_CLAIM_CONSUMED_NO_RESULT') {
    const scenarioRoot = path.join(await realpath(e2eRoot), scenarioSha256);
    await mkdir(scenarioRoot, { recursive: true, mode: 0o700 });
    const [phase, boundary] = scenarioId.split(':');
    const receipt = {
      schema_version: 1, purpose: 'CI3_SYNTHETIC_OPERATIONAL_E2E_RECEIPT_V2',
      scenario_id: scenarioId, scenario_sha256: scenarioSha256, phase, boundary,
      crash_observed: true, recovery_resumed: false, effect_count_at_most_one: true,
      launcher_snapshot: 'GIT_BOUND', controller_state: outcome.state,
      writer_mode: 'NOT_INVOKED', pre_anchor_state: 'NOT_PUBLISHED', terminal_state: 'NOT_PUBLISHED',
      scan_ids: outcome.scan_ids, raw_values: false,
    };
    await writeFile(path.join(scenarioRoot, 'e2e.receipt.json'), canonicalJson(receipt), { flag: 'wx', mode: 0o600 });
    return receipt;
  }
  const descriptor = await readSyntheticWriterDescriptor({
    authority: { commit: outcome.authority_sha }, generations: outcome.generations,
  });
  const preAnchorBytes = await readFile(descriptor.anchor_path);
  const settlementPath = path.join(descriptor.anchor_root, descriptor.authority,
    descriptor.generations.terminal, 'terminal-settlement.json');
  const settlementBytes = await readFile(settlementPath);
  let preAnchor;
  let settlement;
  try {
    preAnchor = JSON.parse(preAnchorBytes);
    settlement = JSON.parse(settlementBytes);
  } catch { fail(code); }
  validateTerminalSettlementReceipt(settlement);
  if (preAnchor.terminal_state !== 'PENDING_VERIFICATION'
      || preAnchor.authority_sha !== descriptor.authority
      || settlement.pre_anchor_sha256 !== sha256(preAnchorBytes)
      || settlement.settlement_sha256 !== outcome.settlement?.settlement_sha256) fail(code);
  const e2ePhysicalRoot = await realpath(e2eRoot);
  const scenarioRoot = path.join(e2ePhysicalRoot, scenarioSha256);
  const scenarioAnchorRoot = path.join(scenarioRoot, 'anchors');
  await mkdir(scenarioAnchorRoot, { recursive: true, mode: 0o700 });
  await writeFile(path.join(scenarioAnchorRoot, 'pre-anchor.json'), preAnchorBytes, { flag: 'wx', mode: 0o600 });
  await writeFile(path.join(scenarioAnchorRoot, 'terminal-settlement.json'), settlementBytes, { flag: 'wx', mode: 0o600 });
  const [phase, boundary] = scenarioId.split(':');
  const receipt = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_OPERATIONAL_E2E_RECEIPT_V2',
    scenario_id: scenarioId,
    scenario_sha256: scenarioSha256,
    phase,
    boundary,
    crash_observed: outcome.crash_observed,
    recovery_resumed: outcome.recovery_resumed,
    effect_count_at_most_one: outcome.effect_count_at_most_one,
    launcher_snapshot: 'GIT_BOUND',
    controller_state: outcome.state,
    writer_mode: 'WRITE',
    pre_anchor_state: preAnchor.terminal_state,
    terminal_state: settlement.terminal_state,
    scan_ids: outcome.scan_ids,
    raw_values: false,
  };
  await writeFile(path.join(scenarioRoot, 'e2e.receipt.json'), canonicalJson(receipt), { flag: 'wx', mode: 0o600 });
  return receipt;
}
export function validateOperationAuthority(record, launchAttestation) {
  const code = 'OPERATION_AUTHORITY';
  exactKeys(record, [
    'context', 'purpose', 'raw_values', 'remote', 'scans', 'schema_version',
    'simulator', 'ssh', 'worktree', 'writer',
  ], code);
  if (record.schema_version !== 1
      || record.purpose !== 'CI3_MAC_OPERATION_AUTHORITY_V1'
      || record.raw_values !== false) fail(code);
  const context = record.context;
  exactKeys(context, ['authority', 'generations', 'remote'], code);
  if (context.authority?.commit !== launchAttestation.authority_sha
      || context.authority?.parent !== launchAttestation.authority_parent
      || context.authority?.tree !== launchAttestation.authority_tree
      || context.authority?.manifest_sha256 !== launchAttestation.authority_manifest_sha256
      || !canonicalJson(context.authority?.components).equals(canonicalJson(launchAttestation.components))) fail(code);
  for (const generation of Object.values(context.generations ?? {})) validateGenerationId(generation);
  exactKeys(record.worktree, ['branch', 'changed_paths', 'continuation_allowlist_sha256', 'diff_sha256', 'head', 'status_sha256'], code);
  if (record.worktree.branch !== 'codex/ci3-today-staging-v1'
      || record.worktree.head !== CI3_PARENT
      || record.worktree.continuation_allowlist_sha256 !== CONTINUATION_ALLOWLIST_SHA256) fail(code);
  validatePreservedCi3Paths(record.worktree.changed_paths);
  requireSha(record.worktree.diff_sha256, code);
  requireSha(record.worktree.status_sha256, code);
  exactKeys(record.simulator, [
    'app_installation_sha256', 'container_identity_sha256', 'container_path_sha256', 'device_selection_sha256',
    'device_udid', 'probe_ack_sha256', 'probe_config_path', 'probe_config_sha256',
    'probe_credential_path', 'probe_credential_sha256', 'runtime_sha256',
  ], code);
  for (const field of [
    'app_installation_sha256', 'container_identity_sha256', 'container_path_sha256', 'device_selection_sha256',
    'probe_ack_sha256', 'probe_config_sha256', 'probe_credential_sha256', 'runtime_sha256',
  ]) requireSha(record.simulator[field], code);
  if (typeof record.simulator.device_udid !== 'string' || !record.simulator.device_udid
      || !path.isAbsolute(record.simulator.probe_config_path)
      || !path.isAbsolute(record.simulator.probe_credential_path)) fail(code);
  exactKeys(record.ssh, [
    'alias', 'code_signature_sha256', 'config_path', 'config_sha256',
    'destination_sha256', 'effective_config_sha256', 'host_key_ed25519_sha256',
    'executable_path_sha256', 'executable_sha256',
    'identity_path', 'identity_public_key_fingerprint_sha256',
    'identity_public_key_path', 'identity_public_key_sha256', 'identity_sha256', 'known_hosts_path',
    'known_hosts_sha256', 'port', 'trust_descriptor_path',
    'trust_descriptor_sha256', 'version_sha256',
  ], code);
  if (!/^ci3-[a-z0-9-]+$/.test(record.ssh.alias) || record.ssh.port < 1 || record.ssh.port > 65535) fail(code);
  for (const field of [
    'code_signature_sha256', 'config_sha256', 'destination_sha256',
    'effective_config_sha256', 'executable_path_sha256', 'executable_sha256', 'host_key_ed25519_sha256',
    'identity_public_key_fingerprint_sha256', 'identity_public_key_sha256', 'identity_sha256',
    'known_hosts_sha256', 'trust_descriptor_sha256', 'version_sha256',
  ]) requireSha(record.ssh[field], code);
  if (record.ssh.executable_path_sha256 !== sha256(Buffer.from(SSH_PATH))
      || record.ssh.executable_sha256 !== launchAttestation.tools.ssh.binary_sha256) fail(code);
  for (const field of ['config_path', 'identity_path', 'identity_public_key_path', 'known_hosts_path', 'trust_descriptor_path']) if (!path.isAbsolute(record.ssh[field])) fail(code);
  exactKeys(record.remote, ['config_path', 'credential_path', 'receipt_path'], code);
  for (const field of ['config_path', 'credential_path', 'receipt_path']) if (typeof record.remote[field] !== 'string' || !record.remote[field].startsWith('/')) fail(code);
  if (context.remote.bundle_path_sha256 !== sha256(Buffer.from(path.dirname(record.remote.config_path)))) fail(code);
  for (const kind of ['receipt', 'config', 'credential']) {
    if (sha256(Buffer.from(record.remote[`${kind}_path`])) !== context.remote[`${kind}_path_sha256`]) fail(code);
  }
  validateScanSurfaceAuthority(record.scans, context.authority.commit, launchAttestation.components.controller.sha256);
  exactKeys(record.writer, ['authority_path', 'manifest_path', 'phase_target_contracts'], code);
  if (!path.isAbsolute(record.writer.authority_path) || !path.isAbsolute(record.writer.manifest_path)) fail(code);
  if (!Array.isArray(record.writer.phase_target_contracts)
      || record.writer.phase_target_contracts.length !== CONTROLLER_EVIDENCE_PHASES.length) fail(code);
  for (let index = 0; index < CONTROLLER_EVIDENCE_PHASES.length; index += 1) {
    const contract = record.writer.phase_target_contracts[index];
    exactKeys(contract, ['phase', 'targets'], code);
    if (contract.phase !== CONTROLLER_EVIDENCE_PHASES[index]
        || !Array.isArray(contract.targets) || contract.targets.length === 0) fail(code);
    for (const target of contract.targets) {
      exactKeys(target, ['allowed_gids', 'allowed_uids', 'immutable', 'modes', 'path_sha256', 'role', 'state'], code);
      if (!/^[a-z0-9-]+$/.test(target.role ?? '') || !['PRESENT', 'ABSENT'].includes(target.state)
          || !Array.isArray(target.modes) || !Array.isArray(target.allowed_uids) || !Array.isArray(target.allowed_gids)
          || typeof target.immutable !== 'boolean') fail(code);
      requireSha(target.path_sha256, code);
      if (target.state === 'PRESENT' && (target.modes.length === 0 || target.allowed_uids.length === 0 || target.allowed_gids.length === 0)) fail(code);
      if (target.state === 'ABSENT' && target.modes.length !== 0) fail(code);
    }
  }
  return record;
}

function runFixedCommand(executable, args, { maxBuffer = 4 * 1024 * 1024 } = {}) {
  const result = spawnSync(executable, args, {
    encoding: null,
    env: CLOSED_BOOTSTRAP_ENVIRONMENT,
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer,
    timeout: 120000,
  });
  if (result.status !== 0 || result.signal || result.error) fail('OPERATION_COMMAND');
  return { stdout: Buffer.from(result.stdout ?? []), stderr: Buffer.from(result.stderr ?? []) };
}

export async function captureCommandToNewFile({
  executable, args, capturePath, expectedSha256, afterOpen,
} = {}) {
  if (!path.isAbsolute(executable ?? '') || !Array.isArray(args)
      || !path.isAbsolute(capturePath ?? '')) fail('REMOTE_CAPTURE_ARGUMENT');
  requireSha(expectedSha256, 'REMOTE_CAPTURE_ARGUMENT');
  const handle = await open(
    capturePath,
    FS_CONSTANTS.O_RDWR | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW,
    0o600,
  ).catch((error) => {
    if (error?.code === 'EEXIST') fail('REMOTE_CAPTURE_EXISTS');
    throw error;
  });
  try {
    const opened = await handle.stat({ bigint: true });
    if (!opened.isFile() || opened.nlink !== 1n || (opened.mode & 0o777n) !== 0o600n
        || opened.uid !== BigInt(process.getuid()) || opened.gid !== BigInt(process.getgid()) || opened.size !== 0n) {
      fail('REMOTE_CAPTURE_PHYSICAL');
    }
    await afterOpen?.();
    const child = spawn(executable, args, {
      env: CLOSED_BOOTSTRAP_ENVIRONMENT,
      stdio: ['ignore', handle.fd, 'pipe'],
    });
    const stderrChunks = [];
    child.stderr.on('data', (chunk) => {
      if (stderrChunks.reduce((total, value) => total + value.length, 0) + chunk.length > 64 * 1024) {
        child.kill('SIGKILL');
        return;
      }
      stderrChunks.push(Buffer.from(chunk));
    });
    const outcome = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => child.kill('SIGKILL'), 120000);
      child.once('error', (error) => { clearTimeout(timeout); reject(error); });
      child.once('close', (status, signal) => { clearTimeout(timeout); resolve({ status, signal }); });
    }).catch(() => fail('REMOTE_CAPTURE_COMMAND'));
    const stderr = Buffer.concat(stderrChunks);
    if (outcome.status !== 0 || outcome.signal !== null || stderr.length !== 0) fail('REMOTE_CAPTURE_COMMAND');
    await handle.sync();
    const completed = await handle.stat({ bigint: true });
    if (completed.dev !== opened.dev || completed.ino !== opened.ino || completed.nlink !== 1n
        || completed.size < 1n || completed.size > BigInt(4 * 1024 * 1024)
        || (completed.mode & 0o777n) !== 0o600n || completed.uid !== opened.uid || completed.gid !== opened.gid) {
      fail('REMOTE_CAPTURE_PHYSICAL');
    }
    const bytes = Buffer.alloc(safeStatNumber(completed.size, 'REMOTE_CAPTURE_PHYSICAL'));
    let offset = 0;
    while (offset < bytes.length) {
      const { bytesRead } = await handle.read(bytes, offset, bytes.length - offset, offset);
      if (bytesRead === 0) fail('REMOTE_CAPTURE_PHYSICAL');
      offset += bytesRead;
    }
    const afterRead = await handle.stat({ bigint: true });
    const finalPath = await lstat(capturePath, { bigint: true }).catch((error) => {
      if (error?.code === 'ENOENT') fail('REMOTE_CAPTURE_RACE');
      throw error;
    });
    const stable = sameBigIntStat(completed, afterRead);
    if (!stable || !finalPath.isFile() || finalPath.isSymbolicLink()
        || finalPath.dev !== completed.dev || finalPath.ino !== completed.ino
        || finalPath.size !== completed.size || finalPath.mtimeNs !== completed.mtimeNs
        || finalPath.mode !== completed.mode || finalPath.nlink !== completed.nlink
        || finalPath.uid !== completed.uid || finalPath.gid !== completed.gid) fail('REMOTE_CAPTURE_RACE');
    if (sha256(bytes) !== expectedSha256) fail('REMOTE_READ');
    await fsyncDirectory(path.dirname(capturePath));
    return {
      bytes,
      descriptor_read: true,
      identity_sha256: physicalIdentityFromBigIntStat(completed).identity_sha256,
    };
  } finally {
    await handle.close();
  }
}

async function readExactOperationalFile(filePath, expectedSha256, code = 'OPERATION_INPUT') {
  requireSha(expectedSha256, code);
  const observed = await lstat(filePath, { bigint: true });
  if (!observed.isFile() || observed.isSymbolicLink() || observed.nlink !== 1n
      || (observed.mode & 0o777n) !== 0o600n
      || observed.uid !== BigInt(process.getuid()) || observed.gid !== BigInt(process.getgid())) fail(code);
  const handle = await open(filePath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
  try {
    const before = await handle.stat({ bigint: true });
    const bytes = await handle.readFile();
    const after = await handle.stat({ bigint: true });
    const finalPath = await lstat(filePath, { bigint: true });
    if (!sameBigIntStat(before, after) || !sameBigIntStat(after, finalPath)
        || sha256(bytes) !== expectedSha256) fail(code);
    return bytes;
  } finally {
    await handle.close();
  }
}

async function readStableScanFile(filePath) {
  const beforePath = await lstat(filePath, { bigint: true });
  if (!beforePath.isFile() || beforePath.isSymbolicLink() || beforePath.nlink !== 1n) fail('TERMINAL_SCAN_INPUT');
  const handle = await open(filePath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
  try {
    const before = await handle.stat({ bigint: true });
    const bytes = await handle.readFile();
    const after = await handle.stat({ bigint: true });
    const afterPath = await lstat(filePath, { bigint: true });
    if (!sameBigIntStat(beforePath, before) || !sameBigIntStat(before, after)
        || !sameBigIntStat(after, afterPath)) fail('TERMINAL_SCAN_INPUT');
    const physical = metadataFromBigIntStat(after, 'TERMINAL_SCAN_INPUT');
    return {
      bytes,
      identity: physical.metadata,
    };
  } finally {
    await handle.close();
  }
}

async function readBoundLocalFile(filePath, {
  code = 'OPERATION_INPUT', expectedSha256 = null, modes = [0o600],
  allowedUids = [process.getuid()], allowedGids = [process.getgid()],
} = {}) {
  if (expectedSha256 !== null) requireSha(expectedSha256, code);
  const beforePath = await lstat(filePath, { bigint: true });
  if (!beforePath.isFile() || beforePath.isSymbolicLink() || beforePath.nlink !== 1n
      || !modes.map(BigInt).includes(beforePath.mode & 0o777n)
      || !allowedUids.map(BigInt).includes(beforePath.uid) || !allowedGids.map(BigInt).includes(beforePath.gid)) fail(code);
  const handle = await open(filePath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
  try {
    const before = await handle.stat({ bigint: true });
    const bytes = await handle.readFile();
    const after = await handle.stat({ bigint: true });
    const afterPath = await lstat(filePath, { bigint: true });
    if (!sameBigIntStat(beforePath, before) || !sameBigIntStat(before, after)
        || !sameBigIntStat(after, afterPath)
        || (expectedSha256 !== null && sha256(bytes) !== expectedSha256)) fail(code);
    const physical = metadataFromBigIntStat(after, code);
    return {
      bytes,
      metadata: physical.metadata,
      identity_sha256: physical.identity_sha256,
    };
  } finally { await handle.close(); }
}

async function evidenceEntry(role, filePath, expectedSha256 = null) {
  const observed = await readBoundLocalFile(filePath, { code: 'TERMINAL_EVIDENCE', expectedSha256 });
  return { role, path: filePath, sha256: sha256(observed.bytes), metadata: observed.metadata };
}

async function ensurePrivateDirectoryChain(basePath, targetPath) {
  const relative = path.relative(basePath, targetPath);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) fail('PRIVATE_DIRECTORY_CHAIN');
  const base = await lstat(basePath);
  if (!base.isDirectory() || base.isSymbolicLink() || base.uid !== process.getuid()) fail('PRIVATE_DIRECTORY_CHAIN');
  let current = basePath;
  for (const [index, segment] of relative.split(path.sep).entries()) {
    current = path.join(current, segment);
    try { await mkdir(current, { mode: 0o700 }); } catch (error) { if (error?.code !== 'EEXIST') throw error; }
    const observed = await lstat(current);
    const mode = observed.mode & 0o777;
    if (!observed.isDirectory() || observed.isSymbolicLink()
        || observed.uid !== process.getuid() || observed.gid !== process.getgid()
        || (index === 0 ? (mode & 0o022) !== 0 : mode !== 0o700)) fail('PRIVATE_DIRECTORY_CHAIN');
    const handle = await open(current, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    await handle.close();
  }
}

async function prepareWriterBinary({ operationStateRoot, sourcePath, sourceSha256, terminalGenerationId }) {
  const source = await readBoundLocalFile(sourcePath, { code: 'TERMINAL_WRITER', expectedSha256: sourceSha256 });
  if (source.bytes.length === 0) fail('TERMINAL_WRITER');
  const buildRoot = path.join(operationStateRoot, 'writer-build', terminalGenerationId);
  await ensurePrivateDirectoryChain(operationStateRoot, buildRoot);
  const binaryPath = path.join(buildRoot, 'ci3-terminal-anchor-writer');
  const existing = await lstat(binaryPath).catch(() => null);
  if (!existing) {
    const stagingPath = path.join(buildRoot, 'ci3-terminal-anchor-writer.staging');
    await lstat(stagingPath).then(() => fail('TERMINAL_WRITER_STAGING_EVIDENCE'), (error) => { if (error?.code !== 'ENOENT') throw error; });
    const compiled = spawnSync(XCRUN_PATH, ['swiftc', '-parse-as-library', '-', '-o', stagingPath], {
      input: source.bytes, encoding: null, env: CLOSED_BOOTSTRAP_ENVIRONMENT,
      stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 4 * 1024 * 1024, timeout: 120000,
    });
    if (compiled.status !== 0 || compiled.signal || compiled.error
        || compiled.stdout.length || compiled.stderr.length) fail('TERMINAL_WRITER');
    await chmod(stagingPath, 0o700);
    const signed = runFixedCommand('/usr/bin/codesign', ['--force', '--sign', '-', stagingPath]);
    if (signed.stdout.length) fail('TERMINAL_WRITER');
    try {
      await link(stagingPath, binaryPath);
    } catch (error) {
      if (error?.code === 'EEXIST') fail('TERMINAL_WRITER_PUBLICATION_RACE');
      throw error;
    }
    await fsyncDirectory(buildRoot);
    await unlink(stagingPath);
    await fsyncDirectory(buildRoot);
  }
  const binary = await readBoundLocalFile(binaryPath, { code: 'TERMINAL_WRITER', modes: [0o700] });
  const signature = runFixedCommand('/usr/bin/codesign', ['-d', '-r-', binaryPath]);
  const signatureBytes = Buffer.concat([signature.stdout, signature.stderr]);
  if (signatureBytes.length === 0) fail('TERMINAL_WRITER');
  return {
    binaryPath,
    binarySha256: sha256(binary.bytes),
    signatureSha256: sha256(signatureBytes),
    sourceSha256: sha256(source.bytes),
  };
}

async function readRootImmutableFile(filePath, expectedSha256, mode, code) {
  if (expectedSha256 !== null) requireSha(expectedSha256, 'STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY');
  const observed = await lstat(filePath, { bigint: true });
  if (!observed.isFile() || observed.isSymbolicLink() || observed.nlink !== 1n
      || observed.uid !== 0n || observed.gid !== 0n || (observed.mode & 0o777n) !== BigInt(mode)) fail(code);
  const flags = runFixedCommand('/usr/bin/stat', ['-f', '%Sf', filePath]);
  if (flags.stderr.length !== 0 || !flags.stdout.toString('utf8').trim().split(',').includes('uchg')) fail(code);
  const handle = await open(filePath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
  try {
    const before = await handle.stat({ bigint: true });
    const bytes = await handle.readFile();
    const after = await handle.stat({ bigint: true });
    const finalPath = await lstat(filePath, { bigint: true });
    if (!sameBigIntStat(before, after) || !sameBigIntStat(after, finalPath)
        || (expectedSha256 !== null && sha256(bytes) !== expectedSha256)) fail(code);
    const physical = metadataFromBigIntStat(after, code);
    return {
      bytes,
      identity_sha256: physical.identity_sha256,
      metadata: physical.metadata,
    };
  } finally { await handle.close(); }
}

async function readRootTerminalDirectory(directoryPath, expectedMode, code) {
  const observed = await lstat(directoryPath, { bigint: true }).catch(() => fail(code));
  if (!observed.isDirectory() || observed.isSymbolicLink() || observed.uid !== 0n || observed.gid !== 0n
      || (observed.mode & 0o777n) !== BigInt(expectedMode) || observed.nlink < 2n) fail(code);
  const handle = await open(
    directoryPath,
    FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_DIRECTORY | FS_CONSTANTS.O_NOFOLLOW,
  ).catch(() => fail(code));
  try {
    const before = await handle.stat({ bigint: true });
    const entries = (await readdir(directoryPath)).sort();
    const after = await handle.stat({ bigint: true });
    const finalPath = await lstat(directoryPath, { bigint: true }).catch(() => fail(code));
    for (const current of [after, finalPath]) {
      if (!current.isDirectory() || current.dev !== before.dev || current.ino !== before.ino
          || current.uid !== before.uid || current.gid !== before.gid || current.mode !== before.mode
          || current.nlink !== before.nlink || current.mtimeNs !== before.mtimeNs
          || current.size !== before.size) fail(code);
    }
    const physical = metadataFromBigIntStat(after, code);
    return {
      entries,
      metadata: physical.metadata,
      identity_sha256: physical.identity_sha256,
    };
  } finally { await handle.close(); }
}

async function readPrivilegedAuthorityFile(filePath, expectedSha256) {
  return (await readRootImmutableFile(
    filePath, expectedSha256, 0o444,
    'STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY',
  )).bytes;
}

function sshValue(records, key, code = 'SSH_POLICY') {
  const values = records.filter((record) => record.key === key).map((record) => record.value);
  if (values.length !== 1) fail(code);
  return values[0];
}

export async function createOperationalRuntime({
  launchAttestation,
  authorityRoot = '/Library/Application Support/Agentempp/ci3-controller-authority',
  stateRoot = path.join(userInfo().homedir, '.config/agentempp/ci3/controller-state'),
}) {
  validateLaunchAttestation(launchAttestation);
  const versionRoot = path.join(authorityRoot, launchAttestation.authority_sha);
  const authorityPath = path.join(versionRoot, 'mac-operation-authority.v1.json');
  const authorityObserved = await lstat(authorityPath).catch(() => fail('STOP_PRE_AUTHORITY'));
  if (!authorityObserved.isFile() || authorityObserved.isSymbolicLink() || authorityObserved.nlink !== 1
      || (authorityObserved.mode & 0o777) !== 0o444
      || authorityObserved.uid !== 0 || authorityObserved.gid !== 0) fail('STOP_PRE_AUTHORITY');
  let authorityRecord;
  try { authorityRecord = JSON.parse((await readPrivilegedAuthorityFile(authorityPath, null)).toString('utf8')); } catch { fail('STOP_PRE_AUTHORITY'); }
  const authority = validateOperationAuthority(authorityRecord, launchAttestation);
  const context = authority.context;
  const expectedSshSnapshotRoot = path.join(versionRoot, 'ssh-snapshots', context.generations.controller);
  const expectedSshSnapshotPaths = {
    config_path: path.join(expectedSshSnapshotRoot, 'ssh_config'),
    known_hosts_path: path.join(expectedSshSnapshotRoot, 'known_hosts'),
    identity_path: path.join(expectedSshSnapshotRoot, 'id_ed25519'),
    identity_public_key_path: path.join(expectedSshSnapshotRoot, 'id_ed25519.pub'),
    trust_descriptor_path: path.join(expectedSshSnapshotRoot, 'trust-descriptor.json'),
  };
  for (const [field, expectedPath] of Object.entries(expectedSshSnapshotPaths)) {
    if (authority.ssh[field] !== expectedPath) fail('SSH_SNAPSHOT_DRIFT');
  }
  const expectedWriterAuthorityPath = path.join(
    '/Library/Application Support/Agentempp/ci3-terminal-authority',
    context.authority.commit, context.generations.terminal, 'privileged-authority.receipt.json',
  );
  const expectedManifestPath = path.join(
    homedir(), '.config/agentempp/ci3/terminal', context.authority.commit,
    context.generations.terminal, 'terminal-anchor.manifest.v1.json',
  );
  if (authority.writer.authority_path !== expectedWriterAuthorityPath
      || authority.writer.manifest_path !== expectedManifestPath) fail('OPERATION_AUTHORITY');
  await mkdir(stateRoot, { recursive: true, mode: 0o700 });
  await chmod(stateRoot, 0o700);
  await ensurePrivateDirectory(stateRoot);
  const operationStateRoot = path.join(stateRoot, launchAttestation.authority_sha);
  await ensurePrivateDirectory(operationStateRoot);
  const journalRoot = path.join(operationStateRoot, 'journal');
  const journalGenerationRoot = path.join(
    journalRoot, context.authority.commit, context.generations.controller,
  );
  const terminalPassPaths = derivePrivilegedTerminalPassPaths({ context, journalGenerationRoot });
  const readTerminalPassMarker = async () => {
    const markerObserved = await lstat(terminalPassPaths.marker).catch(() => null);
    if (markerObserved === null) return null;
    const terminalRoot = path.dirname(terminalPassPaths.marker);
    const phaseRoot = path.dirname(terminalPassPaths.invokeWriterClaim);
    const writerRoot = path.join(terminalRoot, 'writer');
    const [terminalDirectory, phaseDirectory, writerDirectory] = await Promise.all([
      readRootTerminalDirectory(terminalRoot, 0o555, 'TERMINAL_TAIL_AUTHORITY'),
      readRootTerminalDirectory(phaseRoot, 0o555, 'TERMINAL_TAIL_AUTHORITY'),
      readRootTerminalDirectory(writerRoot, 0o555, 'TERMINAL_TAIL_AUTHORITY'),
    ]);
    validatePrivilegedTerminalRootDirectoryEntries({
      terminalEntries: terminalDirectory.entries, phaseEntries: phaseDirectory.entries,
      writerEntries: writerDirectory.entries,
    });
    const roots = Object.fromEntries(await Promise.all(PRIVILEGED_TERMINAL_PATH_KEYS.map(async (key) => [
      key,
      await readRootImmutableFile(terminalPassPaths[key], null, 0o444, 'TERMINAL_TAIL_AUTHORITY'),
    ])));
    const authorityRootObject = parseTerminalRootObject(
      roots.privilegedAuthority.bytes, 'TERMINAL_TAIL_AUTHORITY',
    );
    const terminalManifestRoot = await readBoundLocalFile(authority.writer.manifest_path, {
      code: 'TERMINAL_TAIL_AUTHORITY', modes: [0o600],
    });
    const terminalManifest = parseTerminalRootObject(
      terminalManifestRoot.bytes, 'TERMINAL_TAIL_AUTHORITY',
    );
    exactKeys(terminalManifest, [
      'anchor_relative_path', 'authority_manifest_sha256', 'authority_sha', 'authority_tree',
      'bootstrap_claim_sha256', 'claim_result_chain_sha256', 'components', 'created_at_utc',
      'evidence', 'generations', 'important_finding_ids', 'local_bundle_sha256',
      'privilege_mode', 'purpose', 'raw_values', 'remote_bundle_sha256', 'scan_receipts',
      'schema_version', 'secret_read', 'simulator_gate_sha256', 'simulator_install_sha256',
      'ssh_provenance_sha256', 'terminal_settlement_contracts', 'terminal_state',
      'writer_authority_path_sha256', 'writer_binary_sha256', 'writer_signature_sha256',
      'writer_source_sha256',
    ], 'TERMINAL_TAIL_AUTHORITY');
    if (terminalManifest.schema_version !== 1
        || terminalManifest.purpose !== 'CI3_TERMINAL_ANCHOR_MANIFEST_V1'
        || terminalManifest.authority_sha !== context.authority.commit
        || terminalManifest.authority_tree !== context.authority.tree
        || terminalManifest.authority_manifest_sha256 !== context.authority.manifest_sha256
        || !canonicalJson(terminalManifest.components).equals(canonicalJson(context.authority.components))
        || !canonicalJson(terminalManifest.generations).equals(canonicalJson(context.generations))
        || terminalManifest.writer_source_sha256 !== context.authority.components.writer.sha256
        || terminalManifest.writer_authority_path_sha256
          !== sha256(Buffer.from(authority.writer.authority_path))
        || terminalManifest.anchor_relative_path
          !== `${context.authority.commit}/${context.generations.terminal}/pre-anchor.json`
        || terminalManifest.terminal_state !== 'PRE_ANCHOR_PENDING_SETTLEMENT'
        || terminalManifest.privilege_mode !== 'MACOS_ROOT_SINGLE_ADMIN_PROMPT'
        || terminalManifest.raw_values !== false || terminalManifest.secret_read !== false
        || !Number.isFinite(Date.parse(terminalManifest.created_at_utc))
        || !terminalManifest.created_at_utc.endsWith('Z')) fail('TERMINAL_TAIL_AUTHORITY');
    for (const field of [
      'writer_binary_sha256', 'writer_signature_sha256', 'writer_source_sha256',
    ]) requireSha(terminalManifest[field], 'TERMINAL_TAIL_AUTHORITY');
    if (!Array.isArray(terminalManifest.evidence)
        || terminalManifest.evidence.length !== TERMINAL_MANIFEST_EVIDENCE_ROLES.length
        || !Array.isArray(terminalManifest.scan_receipts)
        || terminalManifest.scan_receipts.length !== TERMINAL_SCAN_IDS.length
        || !canonicalJson(terminalManifest.important_finding_ids)
          .equals(canonicalJson(IMPORTANT_FINDINGS.map(({ id }) => id)))) {
      fail('TERMINAL_TAIL_AUTHORITY');
    }
    const evidenceByRole = new Map();
    for (let index = 0; index < TERMINAL_MANIFEST_EVIDENCE_ROLES.length; index += 1) {
      const entry = terminalManifest.evidence[index];
      exactKeys(entry, ['metadata', 'path', 'role', 'sha256'], 'TERMINAL_TAIL_AUTHORITY');
      exactKeys(entry.metadata, ['dev', 'gid', 'ino', 'mode', 'mtime_ns', 'nlink', 'size', 'uid'], 'TERMINAL_TAIL_AUTHORITY');
      requireSha(entry.sha256, 'TERMINAL_TAIL_AUTHORITY');
      const isRootEvidence = TERMINAL_ROOT_EVIDENCE_ROLES.has(entry.role);
      if (entry.role !== TERMINAL_MANIFEST_EVIDENCE_ROLES[index]
          || !path.isAbsolute(entry.path)
          || entry.metadata.mode !== (isRootEvidence ? 0o444 : 0o600)
          || entry.metadata.nlink !== 1
          || (isRootEvidence && (entry.metadata.uid !== 0 || entry.metadata.gid !== 0))) {
        fail('TERMINAL_TAIL_AUTHORITY');
      }
      evidenceByRole.set(entry.role, entry);
    }
    for (let index = 0; index < TERMINAL_SCAN_IDS.length; index += 1) {
      const entry = terminalManifest.scan_receipts[index];
      exactKeys(entry, ['id', 'metadata', 'path', 'sha256'], 'TERMINAL_TAIL_AUTHORITY');
      exactKeys(entry.metadata, ['dev', 'gid', 'ino', 'mode', 'mtime_ns', 'nlink', 'size', 'uid'], 'TERMINAL_TAIL_AUTHORITY');
      requireSha(entry.sha256, 'TERMINAL_TAIL_AUTHORITY');
      if (entry.id !== TERMINAL_SCAN_IDS[index] || !path.isAbsolute(entry.path)
          || entry.metadata.mode !== 0o600 || entry.metadata.nlink !== 1) fail('TERMINAL_TAIL_AUTHORITY');
    }
    const externalRoles = [
      'operation-authority-root', 'vps-pass-root', 'vps-issuer-authority-root',
      'human-authorization-root', 'publisher-input-manifest-root',
      'ssh-trust-descriptor', 'ssh-public-key', 'ssh-public-key-fingerprint',
    ];
    const externalAuthorityRoots = externalRoles.map((role) => {
      const entry = evidenceByRole.get(role);
      if (!entry) fail('TERMINAL_TAIL_AUTHORITY');
      return { role, sha256: entry.sha256 };
    });
    const phaseTargetRoots = [];
    for (const phase of CONTROLLER_EVIDENCE_PHASES) {
      const role = `${simulatorRolePrefix(phase).replace('simulator-phase', 'controller-phase')}-receipt`;
      const entry = evidenceByRole.get(role);
      if (!entry) fail('TERMINAL_TAIL_AUTHORITY');
      const observed = await readBoundLocalFile(entry.path, {
        code: 'TERMINAL_TAIL_AUTHORITY', expectedSha256: entry.sha256, modes: [0o600],
      });
      if (!canonicalJson(observed.metadata).equals(canonicalJson(entry.metadata))) fail('TERMINAL_TAIL_AUTHORITY');
      const receipt = parseTerminalRootObject(observed.bytes, 'TERMINAL_TAIL_AUTHORITY');
      exactKeys(receipt, [
        'claim_sha256', 'observation', 'phase', 'purpose', 'raw_values', 'result',
        'result_sha256', 'schema_version',
      ], 'TERMINAL_TAIL_AUTHORITY');
      if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1'
          || receipt.phase !== phase || receipt.raw_values !== false
          || receipt.result_sha256 !== sha256(canonicalJson(receipt.result))) fail('TERMINAL_TAIL_AUTHORITY');
      validatePhysicalEffectObservation(receipt.observation, phase);
      phaseTargetRoots.push({
        phase, receipt_sha256: entry.sha256,
        targets_sha256: sha256(canonicalJson(receipt.observation.targets)),
      });
    }
    const writerPath = privilegedWriterExecutablePath(
      context.authority.commit, context.generations.terminal,
    );
    const writerBinary = await readRootImmutableFile(
      writerPath, terminalManifest.writer_binary_sha256, 0o555, 'TERMINAL_TAIL_AUTHORITY',
    );
    const semanticEvidenceReceipt = validateTerminalManifestEvidenceWithCanonicalWriter({
      writerPath, manifestPath: authority.writer.manifest_path, context,
      expectedManifestSha256: sha256(terminalManifestRoot.bytes),
      expectedWriterBinarySha256: terminalManifest.writer_binary_sha256,
      expectedWriterSignatureSha256: terminalManifest.writer_signature_sha256,
      expectedWriterIdentitySha256: writerBinary.identity_sha256,
    });
    const semanticRoots = semanticEvidenceReceipt.semantic_roots;
    const expectedSettlementContracts = semanticEvidenceReceipt.terminal_settlement_contracts;
    const manifestEvidenceRoots = terminalManifest.evidence.map(({ role, sha256: value }) => ({
      role, sha256: value,
    }));
    const manifestScanRoots = terminalManifest.scan_receipts.map(({ id, sha256: value }) => ({
      id, sha256: value,
    }));
    if (!canonicalJson(semanticEvidenceReceipt.evidence_roots).equals(canonicalJson(manifestEvidenceRoots))
        || !canonicalJson(semanticEvidenceReceipt.scan_receipt_roots).equals(canonicalJson(manifestScanRoots))
        || !canonicalJson(semanticRoots.external_authority_roots).equals(canonicalJson(externalAuthorityRoots))
        || !canonicalJson(semanticRoots.phase_target_roots).equals(canonicalJson(phaseTargetRoots))) {
      fail('TERMINAL_TAIL_AUTHORITY');
    }
    const localCompleteEvent = await readBoundLocalFile(
      path.join(journalGenerationRoot, 'events', 'COMPLETE.json'),
      { code: 'TERMINAL_TAIL_AUTHORITY', modes: [0o600] },
    );
    if (!localCompleteEvent.bytes.equals(roots.completeEvent.bytes)) fail('TERMINAL_TAIL_AUTHORITY');
    const privilegedClaimPath = path.join(
      path.dirname(authority.writer.manifest_path), 'privileged-anchor.claim.json',
    );
    const privilegedClaimRoot = await readBoundLocalFile(privilegedClaimPath, {
      code: 'TERMINAL_TAIL_AUTHORITY', modes: [0o600, 0o400],
    });
    const privilegedClaim = parseTerminalRootObject(
      privilegedClaimRoot.bytes, 'TERMINAL_TAIL_AUTHORITY',
    );
    const expectedPrivilegedClaim = buildPrivilegedPublisherClaim({
      authoritySha: context.authority.commit,
      terminalGenerationId: context.generations.terminal,
      terminalManifestSha256: sha256(terminalManifestRoot.bytes),
      writerSourceSha256: terminalManifest.writer_source_sha256,
      writerBinarySha256: terminalManifest.writer_binary_sha256,
      anchorPathSha256: sha256(Buffer.from(terminalPassPaths.preAnchor)),
    });
    if (!canonicalJson(privilegedClaim).equals(canonicalJson(expectedPrivilegedClaim))) {
      fail('TERMINAL_TAIL_AUTHORITY');
    }
    const privilegedClaimSha256 = sha256(privilegedClaimRoot.bytes);
    let marker;
    try { marker = JSON.parse(roots.marker.bytes.toString('utf8')); } catch { fail('TERMINAL_TAIL_AUTHORITY'); }
    const inputs = {
      authorityExpected: {
        authoritySha: context.authority.commit,
        terminalGenerationId: context.generations.terminal,
        terminalManifestSha256: sha256(terminalManifestRoot.bytes),
        writerSourceSha256: terminalManifest.writer_source_sha256,
        writerBinarySha256: terminalManifest.writer_binary_sha256,
        writerSignatureSha256: terminalManifest.writer_signature_sha256,
        privilegedClaimSha256,
        authorityPathSha256: sha256(Buffer.from(authority.writer.authority_path)),
        anchorPathSha256: sha256(Buffer.from(terminalPassPaths.preAnchor)),
        terminalManifestPathSha256: sha256(Buffer.from(authority.writer.manifest_path)),
        writerExecutablePathSha256: sha256(Buffer.from(writerPath)),
        writerExecutableIdentitySha256: writerBinary.identity_sha256,
      },
      preAnchorExpected: {
        authorityTree: terminalManifest.authority_tree,
        authorityManifestSha256: semanticRoots.authority_manifest_sha256,
        components: structuredClone(terminalManifest.components),
        writerSourceSha256: terminalManifest.writer_source_sha256,
        writerBinarySha256: terminalManifest.writer_binary_sha256,
        writerSignatureSha256: terminalManifest.writer_signature_sha256,
        generations: structuredClone(terminalManifest.generations),
        bootstrapClaimSha256: semanticRoots.bootstrap_claim_sha256,
        claimResultChainSha256: semanticRoots.claim_result_chain_sha256,
        remoteBundleSha256: semanticRoots.remote_bundle_sha256,
        localBundleSha256: semanticRoots.local_bundle_sha256,
        sshProvenanceSha256: semanticRoots.ssh_provenance_sha256,
        simulatorGateSha256: semanticRoots.simulator_gate_sha256,
        simulatorInstallSha256: semanticRoots.simulator_install_sha256,
        writerAuthorityPathSha256: terminalManifest.writer_authority_path_sha256,
        privilegedClaimSha256, evidenceChainSha256: semanticRoots.evidence_chain_sha256,
        externalAuthorityRoots: structuredClone(semanticRoots.external_authority_roots),
        phaseTargetRoots: structuredClone(semanticRoots.phase_target_roots),
        scanReceipts: structuredClone(semanticRoots.scan_receipts),
        terminalSettlementContractsSha256:
          semanticEvidenceReceipt.terminal_settlement_contracts_sha256,
        createdAtUtc: terminalManifest.created_at_utc,
      },
      semanticEvidenceReceipt,
      authorityReceiptBytes: roots.privilegedAuthority.bytes,
      completeBytes: roots.completeResult.bytes,
      completeEventBytes: roots.completeEvent.bytes,
      completeFinalScanBytes: roots.completeFinalScan.bytes,
      invokeWriterClaimBytes: roots.invokeWriterClaim.bytes,
      invokeWriterReceiptBytes: roots.invokeWriterReceipt.bytes,
      invokeWriterResultBytes: roots.invokeWriterResult.bytes,
      journalFrameBytes: roots.journalFrame.bytes,
      preAnchorBytes: roots.preAnchor.bytes,
      settlementBytes: roots.settlement.bytes,
      stderrBytes: roots.stderrFrame.bytes,
      stdoutBytes: roots.stdoutFrame.bytes,
      terminalFinalScanBytes: roots.terminalFinalScan.bytes,
      verifyAnchorClaimBytes: roots.verifyAnchorClaim.bytes,
      verifyAnchorReceiptBytes: roots.verifyAnchorReceipt.bytes,
      verifyAnchorResultBytes: roots.verifyAnchorResult.bytes,
      writerOutputBytes: roots.writerOutput.bytes,
    };
    const rootObservations = Object.fromEntries(PRIVILEGED_TERMINAL_PATH_KEYS
      .filter((key) => key !== 'marker')
      .map((key) => [key, { identity_sha256: roots[key].identity_sha256, metadata: roots[key].metadata }]));
    validatePrivilegedTerminalPassCorpus({
      marker, context, paths: terminalPassPaths, rootObservations, ...inputs,
    });
    return {
      marker, markerBytes: roots.marker.bytes, markerSha256: sha256(roots.marker.bytes),
      paths: terminalPassPaths, inputs, terminalDirectory: terminalDirectory.metadata,
      phaseDirectory: phaseDirectory.metadata, writerDirectory: writerDirectory.metadata,
      writerBinary: { identity_sha256: writerBinary.identity_sha256, metadata: writerBinary.metadata },
    };
  };
  const journal = await createVersionedJournal({
    root: journalRoot,
    authoritySha: context.authority.commit,
    controllerGenerationId: context.generations.controller,
    terminalAuthority: { context, readMarker: readTerminalPassMarker },
  });
  const capturesRoot = path.join(operationStateRoot, 'captures');
  await ensurePrivateDirectory(capturesRoot);
  const terminalEvidenceRoot = path.join(operationStateRoot, 'terminal-evidence');
  await ensurePrivateDirectory(terminalEvidenceRoot);
  const phaseEvidenceRoot = path.join(operationStateRoot, 'phase-effect-evidence');
  await ensurePrivateDirectory(phaseEvidenceRoot);
  const worktreeObservationPath = path.join(phaseEvidenceRoot, 'worktree-observation.json');
  const simulatorGateReceiptPath = path.join(phaseEvidenceRoot, 'simulator-gate.receipt.json');
  const sshProvenancePath = path.join(phaseEvidenceRoot, 'ssh-provenance.json');
  const sshFingerprintPath = path.join(phaseEvidenceRoot, 'ssh-public-key-fingerprint.txt');
  const expectedAnchorPath = path.join(
    '/Library/Application Support/Agentempp/ci3-terminal-authority',
    context.authority.commit, context.generations.terminal, 'pre-anchor.json',
  );
  const captures = new Map();
  let sshSnapshotBaseline = null;
  const observeSshPhysicalSnapshot = async () => {
    const snapshot = {};
    for (const [role, filePath, expected] of [
      ['config', authority.ssh.config_path, authority.ssh.config_sha256],
      ['known_hosts', authority.ssh.known_hosts_path, authority.ssh.known_hosts_sha256],
      ['identity', authority.ssh.identity_path, authority.ssh.identity_sha256],
      ['public_key', authority.ssh.identity_public_key_path, authority.ssh.identity_public_key_sha256],
      ['trust_descriptor', authority.ssh.trust_descriptor_path, authority.ssh.trust_descriptor_sha256],
    ]) {
      const before = await lstat(filePath, { bigint: true }).catch(() => fail('SSH_SNAPSHOT_DRIFT'));
      const expectedMode = role === 'identity' ? 0o400 : 0o444;
      if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1n
          || before.uid !== 0n || before.gid !== 0n || (before.mode & 0o777n) !== BigInt(expectedMode)) fail('SSH_SNAPSHOT_DRIFT');
      const bytes = await readExactOperationalFile(filePath, expected, 'SSH_SNAPSHOT_DRIFT');
      const after = await lstat(filePath, { bigint: true }).catch(() => fail('SSH_SNAPSHOT_DRIFT'));
      if (!sameBigIntStat(before, after)) fail('SSH_SNAPSHOT_DRIFT');
      snapshot[role] = {
        path: filePath, sha256: sha256(bytes),
        identity_sha256: physicalIdentityFromBigIntStat(after).identity_sha256,
      };
    }
    return snapshot;
  };
  const simulatorContainer = { path: null, identitySha256: null };
  const getContainer = async () => {
    const result = runFixedCommand(XCRUN_PATH, ['simctl', 'get_app_container', authority.simulator.device_udid, BUNDLE_ID, 'data']);
    if (result.stderr.length !== 0) fail('SIMULATOR_GATE');
    const candidate = result.stdout.toString('utf8').trim();
    if (!path.isAbsolute(candidate) || sha256(Buffer.from(candidate)) !== authority.simulator.container_path_sha256) fail('SIMULATOR_GATE');
    const resolved = await realpath(candidate);
    const observed = await observeSimulatorContainerIdentity(resolved);
    simulatorContainer.path = resolved;
    simulatorContainer.identitySha256 = observed.identity_sha256;
    if (simulatorContainer.identitySha256 !== authority.simulator.container_identity_sha256) fail('SIMULATOR_GATE');
    return resolved;
  };
  const finalizeTerminalEvidence = async ({ local, installed, readResults, receipts }) => {
    const inputManifestPath = path.join(terminalEvidenceRoot, 'input-manifest.json');
    const authorityManifestPath = path.join(terminalEvidenceRoot, 'authority-manifest.json');
    const launchAttestationPath = path.join(terminalEvidenceRoot, 'launch-attestation.json');
    const writerSourcePath = path.join(terminalEvidenceRoot, 'writer-source.swift');
    const durableJournalFramePath = path.join(terminalEvidenceRoot, 'controller-durable-state-root.json');
    await materializeActualJournalFrame({
      generationRoot: journal.paths.generationRoot,
      destinationPath: durableJournalFramePath,
      context,
    });
    const preparedWriter = await prepareWriterBinary({
      operationStateRoot, sourcePath: writerSourcePath,
      sourceSha256: context.authority.components.writer.sha256,
      terminalGenerationId: context.generations.terminal,
    });
    const scanPointers = [];
    for (const scanId of TERMINAL_SCAN_IDS) {
      const scanPath = path.join(terminalEvidenceRoot, `scan-${scanId}.json`);
      const entry = await evidenceEntry(scanId, scanPath);
      scanPointers.push({ id: scanId, path: entry.path, sha256: entry.sha256, metadata: entry.metadata });
    }
    const runScansPhaseResult = await journal.loadPhaseResult('RUN_SCANS');
    if (!runScansPhaseResult) fail('TERMINAL_EVIDENCE');
    const runScansResultSha256 = sha256(canonicalJson(runScansPhaseResult));
    const terminalSettlementContracts = buildTerminalSettlementContracts({
      authoritySha: context.authority.commit,
      controllerGenerationId: context.generations.controller,
      terminalGenerationId: context.generations.terminal,
      runScansResultSha256,
    });
    const terminalReceipt = {
      schema_version: 1,
      purpose: 'CI3_TERMINAL_PREPARATION_RECEIPT_V1',
      authority_sha: context.authority.commit,
      controller_generation_id: context.generations.controller,
      terminal_generation_id: context.generations.terminal,
      scan_receipt_sha256: scanPointers.map(({ id, sha256: value }) => ({ id, sha256: value })),
      run_scans_result_sha256: runScansResultSha256,
      terminal_settlement_contracts_sha256: sha256(canonicalJson(terminalSettlementContracts)),
      writer_source_sha256: preparedWriter.sourceSha256,
      writer_binary_sha256: preparedWriter.binarySha256,
      writer_signature_sha256: preparedWriter.signatureSha256,
      privileged_authority_path_sha256: sha256(Buffer.from(authority.writer.authority_path)),
      normal_executor_authorized: false,
      finished_at: receipts.at(-1)?.finished_at,
      raw_values: false,
    };
    if (!Number.isFinite(Date.parse(terminalReceipt.finished_at))) fail('TERMINAL_EVIDENCE');
    const terminalReceiptPath = path.join(terminalEvidenceRoot, 'terminal-preparation.receipt.json');
    await writeOnceJson(terminalReceiptPath, terminalReceipt);
    const evidencePaths = [
      ['authority-manifest', authorityManifestPath],
      ['launch-attestation', launchAttestationPath],
      ['bootstrap-claim', journal.paths.claim('bootstrap')],
      ['receipt-read-claim', journal.paths.claim('receipt')],
      ['receipt-read-result', journal.paths.result('receipt')],
      ['config-read-claim', journal.paths.claim('config')],
      ['config-read-result', journal.paths.result('config')],
      ['credential-read-claim', journal.paths.claim('credential')],
      ['credential-read-result', journal.paths.result('credential')],
      ['remote-receipt', path.join(capturesRoot, 'receipt.capture')],
      ['local-receipt', path.join(local.root, 'local-bridge.receipt.json')],
      ['ssh-provenance', journal.paths.event('VERIFY_SSH')],
      ['simulator-gate', journal.paths.event('VERIFY_SIMULATOR')],
      ['simulator-install', installed.install_receipt_path],
      ['input-manifest', inputManifestPath],
      ['terminal-receipt', terminalReceiptPath],
      ['controller-durable-state-root', durableJournalFramePath],
      ['writer-source', writerSourcePath],
      ['operation-authority-root', authorityPath],
      ['vps-pass-root', path.join(versionRoot, 'vps-operation-authority.pass.json')],
      ['vps-issuer-authority-root', path.join(versionRoot, 'vps-issuer-authority.receipt.json')],
      ['human-authorization-root', path.join(versionRoot, 'human-authorization.receipt.json')],
      ['publisher-input-manifest-root', path.join(versionRoot, 'publisher-input.manifest.json')],
      ['ssh-trust-descriptor', path.join(versionRoot, 'ssh-trust-descriptor.json')],
      ['ssh-public-key', path.join(versionRoot, 'ssh-identity.pub')],
      ['ssh-public-key-fingerprint', sshFingerprintPath],
    ];
    const simulatorPhaseRoot = path.join(operationStateRoot, 'simulator-phases');
    for (const phase of SIMULATOR_PHASES) {
      const prefix = simulatorRolePrefix(phase);
      evidencePaths.push(
        [`${prefix}-claim`, path.join(simulatorPhaseRoot, `${phase}.claim.json`)],
        [`${prefix}-receipt`, path.join(simulatorPhaseRoot, `${phase}.receipt.json`)],
        [`${prefix}-result`, path.join(simulatorPhaseRoot, `${phase}.result.json`)],
      );
    }
    for (const phase of CONTROLLER_EVIDENCE_PHASES) {
      const prefix = `controller-phase-${phase.toLowerCase().replaceAll('_', '-')}`;
      evidencePaths.push(
        [`${prefix}-claim`, journal.paths.phaseClaim(phase)],
        [`${prefix}-receipt`, journal.paths.phaseReceipt(phase)],
        [`${prefix}-result`, journal.paths.phaseResult(phase)],
      );
    }
    const evidence = [];
    const rootEvidenceRoles = new Set([
      'operation-authority-root', 'vps-pass-root', 'vps-issuer-authority-root',
      'human-authorization-root', 'publisher-input-manifest-root',
      'ssh-trust-descriptor', 'ssh-public-key',
    ]);
    for (const [role, filePath] of evidencePaths) {
      if (rootEvidenceRoles.has(role)) {
        const observed = await readRootImmutableFile(filePath, null, 0o444, 'TERMINAL_EVIDENCE');
        evidence.push({ role, path: filePath, sha256: sha256(observed.bytes), metadata: observed.metadata });
      } else evidence.push(await evidenceEntry(role, filePath));
    }
    const bootstrapClaim = await journal.loadClaim('bootstrap');
    const readClaims = [];
    const durableReadResults = [];
    for (const kind of ['receipt', 'config', 'credential']) {
      readClaims.push(await journal.loadClaim(kind));
      durableReadResults.push(await journal.loadResult(kind));
    }
    if (!bootstrapClaim || readClaims.some((value) => !value) || durableReadResults.some((value) => !value)
        || !canonicalJson(readResults).equals(canonicalJson(durableReadResults))) fail('TERMINAL_EVIDENCE');
    const evidenceByRole = Object.fromEntries(evidence.map((entry) => [entry.role, entry]));
    const readEvidenceRoles = [
      'receipt-read-claim', 'receipt-read-result', 'config-read-claim',
      'config-read-result', 'credential-read-claim', 'credential-read-result',
    ];
    const manifest = buildTerminalManifest({
      authoritySha: context.authority.commit,
      authorityTree: context.authority.tree,
      authorityManifestSha256: context.authority.manifest_sha256,
      components: context.authority.components,
      generations: context.generations,
      bootstrapClaimSha256: evidenceByRole['bootstrap-claim'].sha256,
      readChainSha256: sha256(Buffer.from(readEvidenceRoles.map((role) => evidenceByRole[role].sha256).join(':'))),
      remoteBundleSha256: evidenceByRole['remote-receipt'].sha256,
      localBundleSha256: evidenceByRole['local-receipt'].sha256,
      sshProvenanceSha256: evidenceByRole['ssh-provenance'].sha256,
      simulatorGateSha256: evidenceByRole['simulator-gate'].sha256,
      installReceiptSha256: evidenceByRole['simulator-install'].sha256,
      scanReceipts: scanPointers,
      evidence,
      writerAuthorityPathSha256: sha256(Buffer.from(authority.writer.authority_path)),
      writerSourceSha256: preparedWriter.sourceSha256,
      writerBinarySha256: preparedWriter.binarySha256,
      writerSignatureSha256: preparedWriter.signatureSha256,
      runScansResultSha256,
      terminalSettlementContracts,
      createdAtUtc: terminalReceipt.finished_at,
    });
    const manifestParent = path.dirname(authority.writer.manifest_path);
    await ensurePrivateDirectoryChain(homedir(), manifestParent);
    await writeOnceBytes(authority.writer.manifest_path, canonicalJson(manifest));
    return { manifest, preparedWriter };
  };
  const adapters = {
    finalizeTerminalEvidence: async ({ local, installed, readResults, scans }) => finalizeTerminalEvidence({
      local, installed, readResults, receipts: scans,
    }),
    observePhase: async ({ event, result }) => {
      const present = async (role, filePath, options = {}) => {
        const first = options.requireImmutable
          ? await readRootImmutableFile(filePath, null, options.modes?.[0] ?? 0o444, 'PHASE_PHYSICAL_OBSERVATION')
          : await readBoundLocalFile(filePath, {
            code: 'PHASE_PHYSICAL_OBSERVATION', modes: options.modes ?? [0o600],
            allowedUids: options.allowedUids ?? [process.getuid()],
            allowedGids: options.allowedGids ?? [process.getgid()],
          });
        return {
          role, path: filePath, state: 'PRESENT', expectedSha256: sha256(first.bytes),
          modes: options.modes, allowedUids: options.allowedUids,
          allowedGids: options.allowedGids, requireImmutable: options.requireImmutable,
        };
      };
      let targets;
      if (event === 'VERIFY_AUTHORITY') {
        targets = [await present('operation-authority', authorityPath, {
          modes: [0o444], allowedUids: [0], allowedGids: [0], requireImmutable: true,
        })];
      } else if (event === 'VERIFY_WORKTREE') {
        const worktree = path.join(homedir(), 'Developer/bodyflow-ci3-today-staging-v1');
        const branch = runFixedCommand('/usr/bin/git', ['-C', worktree, 'branch', '--show-current']).stdout.toString('utf8').trim();
        const head = runFixedCommand('/usr/bin/git', ['-C', worktree, 'rev-parse', 'HEAD']).stdout.toString('utf8').trim();
        const status = runFixedCommand('/usr/bin/git', ['-C', worktree, 'status', '--short', '--untracked-files=all']).stdout;
        const diff = runFixedCommand('/usr/bin/git', ['-C', worktree, 'diff', '--binary', '--no-ext-diff']).stdout;
        const changedPaths = status.toString('utf8').trim().split('\n').filter(Boolean).map((line) => line.slice(3)).sort();
        if (branch !== authority.worktree.branch || head !== authority.worktree.head
            || sha256(status) !== authority.worktree.status_sha256
            || sha256(diff) !== authority.worktree.diff_sha256
            || !canonicalJson(changedPaths).equals(canonicalJson([...authority.worktree.changed_paths].sort()))) {
          fail('PHASE_PHYSICAL_OBSERVATION');
        }
        targets = [await present('worktree-observation', worktreeObservationPath)];
      } else if (event === 'VERIFY_SIMULATOR') {
        const devices = runFixedCommand(XCRUN_PATH, ['simctl', 'list', 'devices', '--json']);
        const runtimes = runFixedCommand(XCRUN_PATH, ['simctl', 'list', 'runtimes', '--json']);
        const applications = runFixedCommand(XCRUN_PATH, ['simctl', 'listapps', authority.simulator.device_udid]);
        if (devices.stderr.length !== 0 || runtimes.stderr.length !== 0 || applications.stderr.length !== 0
            || sha256(devices.stdout) !== authority.simulator.device_selection_sha256
            || sha256(runtimes.stdout) !== authority.simulator.runtime_sha256
            || sha256(applications.stdout) !== authority.simulator.app_installation_sha256) {
          fail('PHASE_PHYSICAL_OBSERVATION');
        }
        targets = [await present('simulator-gate-receipt', simulatorGateReceiptPath)];
      } else if (event === 'VERIFY_SSH') {
        for (const [filePath, expected] of [
          [authority.ssh.config_path, authority.ssh.config_sha256],
          [authority.ssh.known_hosts_path, authority.ssh.known_hosts_sha256],
          [authority.ssh.identity_path, authority.ssh.identity_sha256],
          [authority.ssh.identity_public_key_path, authority.ssh.identity_public_key_sha256],
          [authority.ssh.trust_descriptor_path, authority.ssh.trust_descriptor_sha256],
        ]) await readExactOperationalFile(filePath, expected, 'PHASE_PHYSICAL_OBSERVATION');
        const effective = await runSshG({ alias: authority.ssh.alias, configPath: authority.ssh.config_path });
        if (effective.sha256 !== authority.ssh.effective_config_sha256
            || sshValue(effective.records, 'user') !== 'root'
            || Number(sshValue(effective.records, 'port')) !== authority.ssh.port
            || sshValue(effective.records, 'identitiesonly') !== 'yes'
            || sshValue(effective.records, 'stricthostkeychecking') !== 'yes'
            || sshValue(effective.records, 'globalknownhostsfile') !== 'none'
            || sshValue(effective.records, 'identityfile') !== authority.ssh.identity_path
            || sshValue(effective.records, 'userknownhostsfile') !== authority.ssh.known_hosts_path
            || sha256(Buffer.from(sshValue(effective.records, 'hostname'))) !== authority.ssh.destination_sha256) {
          fail('PHASE_PHYSICAL_OBSERVATION');
        }
        const publicFingerprint = runFixedCommand('/usr/bin/ssh-keygen', ['-lf', authority.ssh.identity_public_key_path, '-E', 'sha256']);
        const hostFingerprint = runFixedCommand('/usr/bin/ssh-keygen', ['-lf', authority.ssh.known_hosts_path, '-E', 'sha256']);
        if (publicFingerprint.stderr.length !== 0
            || sha256(publicFingerprint.stdout) !== authority.ssh.identity_public_key_fingerprint_sha256
            || hostFingerprint.stderr.length !== 0
            || sha256(hostFingerprint.stdout) !== authority.ssh.host_key_ed25519_sha256) fail('PHASE_PHYSICAL_OBSERVATION');
        targets = [await present('ssh-provenance-receipt', sshProvenancePath)];
      } else if (event === 'PUBLISH_LOCAL') {
        const expectedRoot = path.join(homedir(), '.config/agentempp/ci3/bundles', context.authority.commit, context.generations.remote);
        if (result?.root !== expectedRoot) fail('PHASE_PHYSICAL_OBSERVATION');
        targets = [await present('local-publication-commit-marker', path.join(expectedRoot, 'local-bridge.receipt.json'))];
      } else if (event === 'INSTALL_SIMULATOR') {
        if (result?.install_receipt_path !== path.join(operationStateRoot, 'simulator-install.receipt.json')) fail('PHASE_PHYSICAL_OBSERVATION');
        targets = [await present('simulator-install-receipt', result.install_receipt_path)];
      } else if (event === 'REMOVE_CREDENTIAL') {
        const containerPath = simulatorContainer.path ?? await getContainer();
        targets = [{
          role: 'simulator-credential',
          path: path.join(containerPath, 'Library/Application Support/Agentempp/synthetic-patient.credentials.json'),
          state: 'ABSENT',
        }];
      } else if (event === 'RUN_SCANS') {
        targets = [];
        for (const id of TERMINAL_SCAN_IDS) {
          targets.push(await present(`terminal-scan-${id}`, path.join(terminalEvidenceRoot, `scan-${id}.json`)));
          targets.push(await present(
            `terminal-surface-${id}`,
            path.join(terminalEvidenceRoot, 'final-surfaces', context.generations.controller, `${id}.surface`),
          ));
          const source = await observeTerminalScanSource({
            scanId: id, root: terminalEvidenceRoot,
            sourcePath: id === 'xcresult'
              ? path.join(terminalEvidenceRoot, 'operational-results', `${context.generations.simulator}.xcresult`)
              : null,
          });
          targets.push(source.state === 'PRESENT'
            ? await present(`terminal-source-${id}`, source.path)
            : { role: `terminal-source-${id}`, path: source.path, state: 'ABSENT' });
        }
      } else if (event === 'INVOKE_WRITER' || event === 'VERIFY_ANCHOR') {
        targets = [await present('terminal-anchor', expectedAnchorPath, {
          modes: [0o444], allowedUids: [0], allowedGids: [0], requireImmutable: true,
        })];
      } else fail('PHASE_PHYSICAL_OBSERVATION');
      return observePhysicalEffect({ phase: event, targets });
    },
    preflightPhase: async ({ event }) => {
      if (event === 'VERIFY_SIMULATOR') {
        const containerPath = simulatorContainer.path ?? await getContainer();
        const appSupport = path.join(containerPath, 'Library/Application Support/Agentempp');
        await assertSimulatorProbeTargetsAbsent([
          path.join(appSupport, 'mobile-staging-config.json'),
          path.join(appSupport, 'synthetic-patient.credentials.json'),
          path.join(appSupport, 'ci3-synthetic-probe.ack.json'),
        ]);
      }
      if (event === 'PUBLISH_LOCAL') {
        const bundleParent = path.join(homedir(), '.config/agentempp/ci3/bundles', context.authority.commit);
        for (const candidate of [
          path.join(bundleParent, context.generations.remote),
          path.join(bundleParent, `.staging-${context.generations.remote}`),
        ]) if (await lstat(candidate).catch(() => null)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
      }
      if (['INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL'].includes(event)) {
        const containerPath = simulatorContainer.path ?? await getContainer();
        const destinationRoot = path.join(containerPath, 'Library/Application Support/Agentempp');
        const installClaimPath = path.join(operationStateRoot, 'simulator-install.claim.json');
        if (event === 'INSTALL_SIMULATOR') {
          if (await lstat(installClaimPath).catch(() => null)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
          for (const name of ['mobile-staging-config.json', 'synthetic-patient.credentials.json']) {
            if (await lstat(path.join(destinationRoot, name)).catch(() => null)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
          }
        } else if (!(await lstat(path.join(destinationRoot, 'synthetic-patient.credentials.json')).catch(() => null))) {
          fail('REJECT_UNCLAIMED_EXISTING_STATE');
        }
      }
      if (event === 'RUN_SCANS') {
        for (const name of [
          'input-manifest.json', 'authority-manifest.json', 'launch-attestation.json',
          'writer-source.swift', 'terminal-preparation.receipt.json',
          'final-sources', 'final-surfaces',
          ...TERMINAL_SCAN_IDS.map((id) => `scan-${id}.json`),
        ]) if (await lstat(path.join(terminalEvidenceRoot, name)).catch(() => null)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
      }
      if (event === 'INVOKE_WRITER') {
        const anchorPath = path.join(
          '/Library/Application Support/Agentempp/ci3-terminal-authority',
          context.authority.commit, context.generations.terminal, 'pre-anchor.json',
        );
        if (await lstat(anchorPath).catch(() => null)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
      }
    },
    publishPrivilegedWriterAuthority: async () => {
      const code = 'PRIVILEGED_AUTHORITY_PUBLISHER';
      const manifestPath = authority.writer.manifest_path;
      const manifest = await readBoundLocalFile(manifestPath, { code: 'TERMINAL_MANIFEST', modes: [0o600] });
      let terminalManifest;
      try { terminalManifest = JSON.parse(manifest.bytes.toString('utf8')); } catch { fail(code); }
      if (terminalManifest.authority_sha !== context.authority.commit
          || terminalManifest.generations?.terminal !== context.generations.terminal
          || terminalManifest.writer_source_sha256 !== context.authority.components.writer.sha256) fail(code);
      const writerSourcePath = path.join(terminalEvidenceRoot, 'writer-source.swift');
      const prepared = await prepareWriterBinary({
        operationStateRoot, sourcePath: writerSourcePath,
        sourceSha256: context.authority.components.writer.sha256,
        terminalGenerationId: context.generations.terminal,
      });
      if (terminalManifest.writer_binary_sha256 !== prepared.binarySha256
          || terminalManifest.writer_signature_sha256 !== prepared.signatureSha256) fail(code);
      const requestPath = path.join(
        homedir(), '.config/agentempp/ci3/publisher-input', context.authority.commit,
        context.generations.terminal, 'privileged-writer.publisher-authorization.json',
      );
      const requestObserved = await readBoundLocalFile(requestPath, { code, modes: [0o600, 0o400] });
      let request;
      try { request = JSON.parse(requestObserved.bytes.toString('utf8')); } catch { fail(code); }
      exactKeys(request, [
        'attempt', 'authority_sha', 'human_authorized', 'purpose', 'raw_values', 'retry',
        'schema_version', 'terminal_generation_id', 'terminal_manifest_sha256',
        'writer_binary_sha256', 'writer_source_sha256',
      ], code);
      const manifestSha256 = sha256(manifest.bytes);
      if (request.schema_version !== 1 || request.purpose !== 'CI3_PRIVILEGED_WRITER_PUBLISHER_AUTHORIZATION_V1'
          || request.authority_sha !== context.authority.commit
          || request.terminal_generation_id !== context.generations.terminal
          || request.terminal_manifest_sha256 !== manifestSha256
          || request.writer_source_sha256 !== prepared.sourceSha256
          || request.writer_binary_sha256 !== prepared.binarySha256
          || request.human_authorized !== true || request.attempt !== 1
          || request.retry !== false || request.raw_values !== false) fail(code);

      const targetRoot = path.dirname(authority.writer.authority_path);
      const writerRoot = path.join(targetRoot, 'writer');
      const writerTarget = privilegedWriterExecutablePath(context.authority.commit, context.generations.terminal);
      const rootClaimPath = path.join(targetRoot, 'privileged-anchor.claim.json');
      const localClaimPath = path.join(path.dirname(manifestPath), 'privileged-anchor.claim.json');
      const expectedAnchorPath = path.join(targetRoot, 'pre-anchor.json');
      const claim = buildPrivilegedPublisherClaim({
        authoritySha: context.authority.commit,
        terminalGenerationId: context.generations.terminal,
        terminalManifestSha256: manifestSha256,
        writerSourceSha256: prepared.sourceSha256,
        writerBinarySha256: prepared.binarySha256,
        anchorPathSha256: sha256(Buffer.from(expectedAnchorPath)),
      });
      const claimBytes = canonicalJson(claim);
      await writeOnceBytes(localClaimPath, claimBytes);
      const operationNodePath = path.join(versionRoot, 'runtime', 'node');
      const operationNode = await readRootImmutableFile(
        operationNodePath, launchAttestation.tools.node.binary_sha256, 0o555, code,
      );
      if (!operationNode.bytes.length) fail(code);
      const rootReceiptScript = [
        "const fs=require('fs'),c=require('crypto')",
        "const [receiptPath,binaryPath,authoritySha,terminalGeneration,manifestSha,sourceSha,binarySha,signatureSha,claimSha,authorityPathSha,anchorPathSha,manifestPathSha,binaryPathSha]=process.argv.slice(1)",
        "const b=fs.readFileSync(binaryPath);if(c.createHash('sha256').update(b).digest('hex')!==binarySha)process.exit(71)",
        "const s=fs.lstatSync(binaryPath,{bigint:true});if(!s.isFile()||s.isSymbolicLink()||s.nlink!==1n||s.uid!==0n||s.gid!==0n||(s.mode&511n)!==365n)process.exit(72)",
        "const identity=c.createHash('sha256').update(`uid=${s.uid};gid=${s.gid};mode=${s.mode&511n};nlink=${s.nlink};size=${s.size};mtime=${s.mtimeNs};dev=${s.dev};ino=${s.ino}`).digest('hex')",
        "const r={schema_version:1,purpose:'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1',authority_sha:authoritySha,terminal_generation_id:terminalGeneration,terminal_manifest_sha256:manifestSha,writer_source_sha256:sourceSha,writer_binary_sha256:binarySha,writer_signature_sha256:signatureSha,privileged_claim_sha256:claimSha,authority_path_sha256:authorityPathSha,anchor_path_sha256:anchorPathSha,terminal_manifest_path_sha256:manifestPathSha,writer_executable_path_sha256:binaryPathSha,writer_executable_identity_sha256:identity,writer_executable_uid:0,writer_executable_gid:0,writer_executable_mode:'0555',writer_executable_immutable_flag:'UF_IMMUTABLE',normal_executor_authorized:false,attempt:1,retry:false,raw_values:false}",
        "const out=Buffer.from(JSON.stringify(Object.fromEntries(Object.entries(r).sort(([a],[b])=>a.localeCompare(b))))+'\\n');const f=fs.openSync(receiptPath,'wx',0o444);fs.writeFileSync(f,out);fs.fsyncSync(f);fs.closeSync(f)",
      ].join(';');
      const immutable = [writerTarget, rootClaimPath, authority.writer.authority_path];
      const commands = [
        'set -eu', 'umask 077',
        `/bin/mkdir -p -m 0555 ${shellQuote(path.dirname(targetRoot))}`,
        `/bin/mkdir -m 0700 ${shellQuote(targetRoot)}`,
        `/bin/mkdir -m 0700 ${shellQuote(writerRoot)}`,
        `/usr/bin/install -m 0400 ${shellQuote(prepared.binaryPath)} ${shellQuote(path.join(targetRoot, '.writer.candidate'))}`,
        `test "$(/usr/bin/shasum -a 256 ${shellQuote(path.join(targetRoot, '.writer.candidate'))} | /usr/bin/awk '{print $1}')" = ${shellQuote(prepared.binarySha256)}`,
        `/usr/bin/install -m 0444 ${shellQuote(localClaimPath)} ${shellQuote(rootClaimPath)}`,
        `test "$(/usr/bin/shasum -a 256 ${shellQuote(rootClaimPath)} | /usr/bin/awk '{print $1}')" = ${shellQuote(sha256(claimBytes))}`,
        `${shellQuote(operationNodePath)} -e ${shellQuote("const fs=require('fs');for(const p of process.argv.slice(1)){const f=fs.openSync(p,'r');fs.fsyncSync(f);fs.closeSync(f)}")} ${shellQuote(rootClaimPath)} ${shellQuote(targetRoot)}`,
        `/usr/bin/install -m 0555 ${shellQuote(path.join(targetRoot, '.writer.candidate'))} ${shellQuote(writerTarget)}`,
        `/bin/rm ${shellQuote(path.join(targetRoot, '.writer.candidate'))}`,
        `test "$(/usr/bin/shasum -a 256 ${shellQuote(writerTarget)} | /usr/bin/awk '{print $1}')" = ${shellQuote(prepared.binarySha256)}`,
        `/usr/sbin/chown -R root:wheel ${shellQuote(targetRoot)}`,
        `/bin/chmod 0555 ${shellQuote(writerTarget)}`,
        `/bin/chmod 0444 ${shellQuote(rootClaimPath)}`,
        `/usr/bin/chflags uchg ${shellQuote(writerTarget)} ${shellQuote(rootClaimPath)}`,
        `${shellQuote(operationNodePath)} -e ${shellQuote(rootReceiptScript)} ${[
          authority.writer.authority_path, writerTarget, context.authority.commit,
          context.generations.terminal, manifestSha256, prepared.sourceSha256,
          prepared.binarySha256, prepared.signatureSha256, sha256(claimBytes),
          sha256(Buffer.from(authority.writer.authority_path)), sha256(Buffer.from(expectedAnchorPath)),
          sha256(Buffer.from(manifestPath)), sha256(Buffer.from(writerTarget)),
        ].map(shellQuote).join(' ')}`,
        `/usr/sbin/chown root:wheel ${shellQuote(authority.writer.authority_path)}`,
        `/bin/chmod 0444 ${shellQuote(authority.writer.authority_path)}`,
        `/usr/bin/chflags uchg ${shellQuote(authority.writer.authority_path)}`,
        `/bin/chmod 0555 ${shellQuote(writerRoot)} ${shellQuote(targetRoot)}`,
        `${shellQuote(operationNodePath)} -e ${shellQuote("const fs=require('fs');for(const p of process.argv.slice(1)){const f=fs.openSync(p,'r');fs.fsyncSync(f);fs.closeSync(f)}")} ${immutable.map(shellQuote).join(' ')} ${shellQuote(writerRoot)} ${shellQuote(targetRoot)} ${shellQuote(path.dirname(targetRoot))}`,
        "printf 'PRIVILEGED_AUTHORITY_PUBLISHER PASS\\n'",
      ];
      runAdminPublisher(commands.join('\n'), code);
      return { status: 'CREATED', raw_values: false };
    },
    recoverPhase: async () => fail('CLAIM_CONSUMED_NO_RESULT'),
    verifyAuthority: async () => {
      validateOperationAuthority(authority, launchAttestation);
      return { authority_manifest_sha256: launchAttestation.authority_manifest_sha256, verified: true };
    },
    verifyWorktree: async () => {
      const worktree = path.join(homedir(), 'Developer/bodyflow-ci3-today-staging-v1');
      const branch = runFixedCommand('/usr/bin/git', ['-C', worktree, 'branch', '--show-current']).stdout.toString('utf8').trim();
      const head = runFixedCommand('/usr/bin/git', ['-C', worktree, 'rev-parse', 'HEAD']).stdout.toString('utf8').trim();
      const status = runFixedCommand('/usr/bin/git', ['-C', worktree, 'status', '--short', '--untracked-files=all']).stdout;
      const diff = runFixedCommand('/usr/bin/git', ['-C', worktree, 'diff', '--binary', '--no-ext-diff']).stdout;
      const changedPaths = status.toString('utf8').trim().split('\n').filter(Boolean).map((line) => line.slice(3)).sort();
      if (branch !== authority.worktree.branch || head !== authority.worktree.head
          || sha256(status) !== authority.worktree.status_sha256
          || sha256(diff) !== authority.worktree.diff_sha256
          || !canonicalJson(changedPaths).equals(canonicalJson([...authority.worktree.changed_paths].sort()))) fail('WORKTREE_AUTHORITY');
      const observation = {
        schema_version: 1, purpose: 'CI3_WORKTREE_PHYSICAL_OBSERVATION_V1',
        authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
        head, status_sha256: sha256(status), diff_sha256: sha256(diff),
        changed_paths_sha256: sha256(canonicalJson(changedPaths)), changed_path_count: changedPaths.length,
        raw_values: false,
      };
      await writeOnceJson(worktreeObservationPath, observation);
      return { status_sha256: sha256(status), diff_sha256: sha256(diff), changed_path_count: changedPaths.length };
    },
    verifySimulator: async () => {
      const phaseRoot = path.join(operationStateRoot, 'simulator-phases');
      await ensurePrivateDirectory(phaseRoot);
      let predecessor = '0'.repeat(64);
      const phaseReceiptHashes = [];
      const settle = async (phase, { effect, preflight = async () => undefined, reobserve }) => {
        const claim = {
          schema_version: 1, purpose: 'CI3_SIMULATOR_PHASE_CLAIM_V1', phase,
          authority_sha: context.authority.commit,
          controller_generation_id: context.generations.controller,
          simulator_generation_id: context.generations.simulator,
          predecessor_result_sha256: predecessor, attempt: 1, retry: false, raw_values: false,
        };
        const claimPath = path.join(phaseRoot, `${phase}.claim.json`);
        const receiptPath = path.join(phaseRoot, `${phase}.receipt.json`);
        const resultPath = path.join(phaseRoot, `${phase}.result.json`);
        const priorClaim = await readPrivateJson(claimPath, true);
        const priorReceipt = await readPrivateJson(receiptPath, true);
        const priorResult = await readPrivateJson(resultPath, true);
        if (priorClaim && !canonicalJson(priorClaim).equals(canonicalJson(claim))) fail('SIMULATOR_GATE');
        if (!priorClaim && (priorReceipt || priorResult)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
        if (!priorClaim) await preflight();
        await writeOnceJson(claimPath, claim);
        if (priorClaim && !priorReceipt) fail('CLAIM_CONSUMED_NO_RESULT');
        const settled = await settleSimulatorPhaseObservation({ priorReceipt, effect, reobserve });
        const observation = settled.observation;
        const receipt = priorReceipt ?? {
          schema_version: 1, purpose: 'CI3_SIMULATOR_PHASE_RECEIPT_V1', phase,
          claim_sha256: sha256(canonicalJson(claim)), observation,
          observation_sha256: sha256(canonicalJson(observation)), physical_reobservation: true,
          raw_values: false,
        };
        if (priorReceipt) {
          exactKeys(priorReceipt, ['claim_sha256', 'observation', 'observation_sha256', 'phase', 'physical_reobservation', 'purpose', 'raw_values', 'schema_version'], 'SIMULATOR_GATE');
          if (priorReceipt.schema_version !== 1 || priorReceipt.purpose !== 'CI3_SIMULATOR_PHASE_RECEIPT_V1'
              || priorReceipt.phase !== phase || priorReceipt.claim_sha256 !== sha256(canonicalJson(claim))
              || priorReceipt.observation_sha256 !== sha256(canonicalJson(priorReceipt.observation))
              || priorReceipt.physical_reobservation !== true || priorReceipt.raw_values !== false) fail('SIMULATOR_GATE');
        } else {
          await writeOnceJson(receiptPath, receipt);
        }
        await readBoundLocalFile(receiptPath, { code: 'SIMULATOR_GATE', modes: [0o600] });
        const physicalObservationSha256 = receipt.observation_sha256;
        const result = {
          schema_version: 1, purpose: 'CI3_SIMULATOR_PHASE_RESULT_V1', phase,
          claim_sha256: sha256(canonicalJson(claim)), receipt_sha256: sha256(canonicalJson(receipt)),
          physical_observation_sha256: physicalObservationSha256,
          observation, terminal_state: 'PHASE_SETTLED', raw_values: false,
        };
        if (priorResult && !canonicalJson(priorResult).equals(canonicalJson(result))) fail('SIMULATOR_GATE');
        await writeOnceJson(resultPath, result);
        predecessor = sha256(canonicalJson(result));
        phaseReceiptHashes.push(sha256(canonicalJson(receipt)));
        return observation;
      };
      const observeDeviceSelection = async () => {
        const list = runFixedCommand(XCRUN_PATH, ['simctl', 'list', 'devices', '--json']);
        if (list.stderr.length !== 0 || sha256(list.stdout) !== authority.simulator.device_selection_sha256) fail('SIMULATOR_GATE');
        return { device_selection_sha256: sha256(list.stdout) };
      };
      await settle('SELECT_DEVICE', { effect: observeDeviceSelection, reobserve: observeDeviceSelection });
      const observeResolvedContainer = async () => {
        const runtimes = runFixedCommand(XCRUN_PATH, ['simctl', 'list', 'runtimes', '--json']);
        const applications = runFixedCommand(XCRUN_PATH, ['simctl', 'listapps', authority.simulator.device_udid]);
        if (runtimes.stderr.length !== 0 || applications.stderr.length !== 0
            || sha256(runtimes.stdout) !== authority.simulator.runtime_sha256
            || sha256(applications.stdout) !== authority.simulator.app_installation_sha256) fail('SIMULATOR_GATE');
        await getContainer();
        return { runtime_sha256: sha256(runtimes.stdout), app_installation_sha256: sha256(applications.stdout), container_identity_sha256: simulatorContainer.identitySha256 };
      };
      await settle('RESOLVE_CONTAINER', { effect: observeResolvedContainer, reobserve: observeResolvedContainer });
      const containerPath = simulatorContainer.path ?? await getContainer();
      const configBytes = await readExactOperationalFile(authority.simulator.probe_config_path, authority.simulator.probe_config_sha256, 'SIMULATOR_GATE');
      const credentialBytes = await readExactOperationalFile(authority.simulator.probe_credential_path, authority.simulator.probe_credential_sha256, 'SIMULATOR_GATE');
      const appSupport = path.join(containerPath, 'Library/Application Support/Agentempp');
      await mkdir(appSupport, { recursive: true, mode: 0o700 });
      const configDestination = path.join(appSupport, 'mobile-staging-config.json');
      const credentialDestination = path.join(appSupport, 'synthetic-patient.credentials.json');
      const observeInstalledProbe = async () => {
        for (const [, destination, expected] of [
          [authority.simulator.probe_config_path, configDestination, authority.simulator.probe_config_sha256],
          [authority.simulator.probe_credential_path, credentialDestination, authority.simulator.probe_credential_sha256],
        ]) await readExactOperationalFile(destination, expected, 'SIMULATOR_GATE');
        return { config_sha256: sha256(configBytes), credential_sha256: sha256(credentialBytes) };
      };
      await settle('INSTALL_PROBE', {
        preflight: () => assertSimulatorProbeTargetsAbsent([configDestination, credentialDestination, path.join(appSupport, 'ci3-synthetic-probe.ack.json')]),
        effect: async () => {
          for (const [source, destination, expected] of [
            [authority.simulator.probe_config_path, configDestination, authority.simulator.probe_config_sha256],
            [authority.simulator.probe_credential_path, credentialDestination, authority.simulator.probe_credential_sha256],
          ]) {
            const installed = runFixedCommand(INSTALL_PATH, ['-m', '0600', source, destination]);
            if (installed.stdout.length || installed.stderr.length) fail('SIMULATOR_GATE');
            await readExactOperationalFile(destination, expected, 'SIMULATOR_GATE');
          }
          return observeInstalledProbe();
        },
        reobserve: observeInstalledProbe,
      });
      const ackPath = path.join(appSupport, 'ci3-synthetic-probe.ack.json');
      const observeLaunch = async () => {
        await readExactOperationalFile(ackPath, authority.simulator.probe_ack_sha256, 'SIMULATOR_GATE');
        return { launch_contract_sha256: sha256(canonicalJson({ device: authority.simulator.device_selection_sha256, bundle: BUNDLE_ID })) };
      };
      await settle('LAUNCH_PROBE', {
        preflight: async () => {
          await lstat(ackPath).then(
            () => fail('REJECT_UNCLAIMED_EXISTING_STATE'),
            (error) => { if (error?.code !== 'ENOENT') throw error; },
          );
        },
        effect: async () => {
          const launched = runFixedCommand(XCRUN_PATH, ['simctl', 'launch', authority.simulator.device_udid, BUNDLE_ID]);
          if (launched.stderr.length !== 0) fail('SIMULATOR_GATE');
          return observeLaunch();
        },
        reobserve: observeLaunch,
      });
      let ackBytes;
      const observeAck = async () => {
        ackBytes = await readExactOperationalFile(ackPath, authority.simulator.probe_ack_sha256, 'SIMULATOR_GATE');
        return { probe_ack_sha256: sha256(ackBytes) };
      };
      await settle('ACK_PROBE', { effect: observeAck, reobserve: observeAck });
      if (!ackBytes) ackBytes = await readExactOperationalFile(ackPath, authority.simulator.probe_ack_sha256, 'SIMULATOR_GATE');
      const observeRemovedProbe = async () => {
        await lstat(credentialDestination).then(() => fail('SIMULATOR_GATE'), (error) => { if (error?.code !== 'ENOENT') throw error; });
        for (const candidate of [configDestination, ackPath]) {
          await lstat(candidate).then(() => fail('SIMULATOR_GATE'), (error) => { if (error?.code !== 'ENOENT') throw error; });
        }
        return { credential_absent: true, controller_files_removed: true };
      };
      await settle('REMOVE_PROBE', { effect: async () => {
        await lstat(credentialDestination).then(() => fail('SIMULATOR_GATE'), (error) => { if (error?.code !== 'ENOENT') throw error; });
        if (await lstat(configDestination).catch(() => null)) await unlink(configDestination);
        if (await lstat(ackPath).catch(() => null)) await unlink(ackPath);
        return observeRemovedProbe();
      }, reobserve: observeRemovedProbe });
      const observeTerminalAbsence = async () => {
        for (const candidate of [configDestination, credentialDestination, ackPath]) {
          await lstat(candidate).then(() => fail('SIMULATOR_GATE'), (error) => { if (error?.code !== 'ENOENT') throw error; });
        }
        return { config_absent: true, credential_absent: true, ack_absent: true };
      };
      await settle('REOBSERVE', { effect: observeTerminalAbsence, reobserve: observeTerminalAbsence });
      const receipt = {
        schema_version: 1, purpose: 'CI3_SIMULATOR_GATE_RECEIPT_V2', authority_sha: context.authority.commit,
        controller_generation_id: context.generations.controller, simulator_generation_id: context.generations.simulator,
        device_selection_sha256: authority.simulator.device_selection_sha256, runtime_sha256: authority.simulator.runtime_sha256,
        app_installation_sha256: authority.simulator.app_installation_sha256, source_commit: CI3_PARENT, bundle_id: BUNDLE_ID,
        container_identity_sha256: simulatorContainer.identitySha256, probe_config_sha256: sha256(configBytes),
        probe_credential_sha256: sha256(credentialBytes), probe_ack_sha256: sha256(ackBytes),
        removal_proof_sha256: predecessor, phases: [...SIMULATOR_PHASES],
        phase_receipt_hashes: phaseReceiptHashes,
        attempts: { select: 1, resolve: 1, install: 1, launch: 1, ack: 1, remove: 1, reobserve: 1 },
        raw_container_path_reported: false, terminal_state: 'SIMULATOR_GATE_PASS',
      };
      validateSimulatorGateReceipt(receipt);
      await writeOnceJson(simulatorGateReceiptPath, receipt);
      return { receipt };
    },
    verifySsh: async () => {
      for (const [filePath, expected] of [
        [authority.ssh.config_path, authority.ssh.config_sha256],
        [authority.ssh.known_hosts_path, authority.ssh.known_hosts_sha256],
        [authority.ssh.identity_path, authority.ssh.identity_sha256],
      ]) {
        await readExactOperationalFile(filePath, expected, 'SSH_AUTHORITY');
      }
      await readExactOperationalFile(authority.ssh.identity_public_key_path, authority.ssh.identity_public_key_sha256, 'SSH_AUTHORITY');
      sshSnapshotBaseline = await observeSshPhysicalSnapshot();
      const effective = await runSshG({ alias: authority.ssh.alias, configPath: authority.ssh.config_path });
      await validateStableSshSnapshots({
        before: sshSnapshotBaseline,
        afterSshG: await observeSshPhysicalSnapshot(),
        afterConnect: sshSnapshotBaseline,
      });
      const trustDescriptorBytes = await readExactOperationalFile(
        authority.ssh.trust_descriptor_path, authority.ssh.trust_descriptor_sha256, 'SSH_AUTHORITY',
      );
      let trustDescriptor;
      try { trustDescriptor = JSON.parse(trustDescriptorBytes.toString('utf8')); } catch { fail('SSH_AUTHORITY'); }
      validateSshTrustDescriptor(trustDescriptor, effective.records, {
        authoritySha: context.authority.commit,
        remoteGenerationId: context.generations.remote,
        executablePathSha256: sha256(Buffer.from(SSH_PATH)),
        executableSha256: authority.ssh.executable_sha256,
        codeSignatureSha256: authority.ssh.code_signature_sha256,
        versionSha256: authority.ssh.version_sha256,
        configSha256: authority.ssh.config_sha256,
        knownHostsSha256: authority.ssh.known_hosts_sha256,
        identityPublicKeySha256: authority.ssh.identity_public_key_sha256,
        identityPublicKeyFingerprintSha256: authority.ssh.identity_public_key_fingerprint_sha256,
        hostKeyFingerprintSha256: authority.ssh.host_key_ed25519_sha256,
        destinationSha256: authority.ssh.destination_sha256,
      });
      if (effective.sha256 !== authority.ssh.effective_config_sha256
          || sshValue(effective.records, 'user') !== 'root'
          || Number(sshValue(effective.records, 'port')) !== authority.ssh.port
          || sshValue(effective.records, 'identitiesonly') !== 'yes'
          || sshValue(effective.records, 'stricthostkeychecking') !== 'yes'
          || sshValue(effective.records, 'globalknownhostsfile') !== 'none'
          || sshValue(effective.records, 'identityfile') !== authority.ssh.identity_path
          || sshValue(effective.records, 'userknownhostsfile') !== authority.ssh.known_hosts_path
          || sha256(Buffer.from(sshValue(effective.records, 'hostname'))) !== authority.ssh.destination_sha256) fail('SSH_AUTHORITY');
      const publicFingerprint = runFixedCommand('/usr/bin/ssh-keygen', ['-lf', authority.ssh.identity_public_key_path, '-E', 'sha256']);
      const hostFingerprint = runFixedCommand('/usr/bin/ssh-keygen', ['-lf', authority.ssh.known_hosts_path, '-E', 'sha256']);
      if (publicFingerprint.stderr.length !== 0
          || sha256(publicFingerprint.stdout) !== authority.ssh.identity_public_key_fingerprint_sha256
          || hostFingerprint.stderr.length !== 0
          || !hostFingerprint.stdout.toString('utf8').includes('(ED25519)')
          || sha256(hostFingerprint.stdout) !== authority.ssh.host_key_ed25519_sha256) fail('SSH_AUTHORITY');
      await writeOnceBytes(sshFingerprintPath, publicFingerprint.stdout);
      const sshBytes = await readFile(SSH_PATH);
      const version = runFixedCommand(SSH_PATH, ['-V']);
      const signature = runFixedCommand('/usr/bin/codesign', ['-d', '-r-', SSH_PATH]);
      const versionBytes = Buffer.concat([version.stdout, version.stderr]);
      const signatureBytes = Buffer.concat([signature.stdout, signature.stderr]);
      const provenance = buildSshProvenance({
        executableSha256: sha256(sshBytes), codeSignatureSha256: sha256(signatureBytes),
        effectiveConfigSha256: effective.sha256, configSha256: authority.ssh.config_sha256,
        knownHostsSha256: authority.ssh.known_hosts_sha256,
        identityPublicKeySha256: authority.ssh.identity_public_key_sha256,
        identityPublicKeyFingerprintSha256: authority.ssh.identity_public_key_fingerprint_sha256,
        hostKeyEd25519Sha256: authority.ssh.host_key_ed25519_sha256,
        destinationSha256: authority.ssh.destination_sha256, versionSha256: sha256(versionBytes),
        trustDescriptorSha256: authority.ssh.trust_descriptor_sha256,
      });
      for (const [field, expected] of [['code_signature_sha256', authority.ssh.code_signature_sha256], ['version_sha256', authority.ssh.version_sha256]]) if (provenance[field] !== expected) fail('SSH_AUTHORITY');
      await writeOnceJson(sshProvenancePath, provenance);
      await validateStableSshSnapshots({
        before: sshSnapshotBaseline,
        afterSshG: sshSnapshotBaseline,
        afterConnect: await observeSshPhysicalSnapshot(),
      });
      return { provenance };
    },
    readRemote: async ({ kind, claim }) => {
      if (!sshSnapshotBaseline) fail('SSH_SNAPSHOT_DRIFT');
      const beforeConnect = await observeSshPhysicalSnapshot();
      await validateStableSshSnapshots({ before: sshSnapshotBaseline, afterSshG: beforeConnect, afterConnect: beforeConnect });
      const remotePath = authority.remote[`${kind}_path`];
      const startedAt = new Date().toISOString();
      const remoteCommand = buildRemoteCatCommand(remotePath);
      const capturePath = path.join(capturesRoot, `${kind}.capture`);
      const captured = await captureCommandToNewFile({
        executable: SSH_PATH,
        args: buildSshReadArgv({ configPath: authority.ssh.config_path, alias: authority.ssh.alias, remotePath }),
        capturePath,
        expectedSha256: claim.expected_sha256,
      });
      await validateStableSshSnapshots({
        before: sshSnapshotBaseline, afterSshG: beforeConnect,
        afterConnect: await observeSshPhysicalSnapshot(),
      });
      const finishedAt = new Date().toISOString();
      const receipt = {
        schema_version: 1, purpose: 'CI3_REMOTE_CAPTURE_RECEIPT_V1', kind,
        claim_sha256: sha256(canonicalJson(claim)), capture_sha256: sha256(captured.bytes),
        capture_identity_sha256: captured.identity_sha256,
        remote_command_sha256: sha256(Buffer.from(remoteCommand)), descriptor_read: true,
        bytes: captured.bytes.length, started_at: startedAt, finished_at: finishedAt, raw_values: false,
      };
      validateRemoteCaptureReceipt(receipt, {
        kind, claim, captureSha256: sha256(captured.bytes),
        captureIdentitySha256: captured.identity_sha256,
        remoteCommandSha256: sha256(Buffer.from(remoteCommand)),
      });
      await writeOnceJson(path.join(capturesRoot, `${kind}.capture.receipt.json`), receipt);
      captures.set(kind, Buffer.from(captured.bytes));
      return { captureSha256: receipt.capture_sha256, captureIdentitySha256: receipt.capture_identity_sha256, remoteCommandSha256: receipt.remote_command_sha256, descriptorRead: true, bytes: receipt.bytes, exit: 0, stderrClass: 'EMPTY', startedAt, finishedAt };
    },
    recoverRemote: async ({ kind, claim }) => {
      const capturePath = path.join(capturesRoot, `${kind}.capture`);
      const receipt = await readPrivateJson(path.join(capturesRoot, `${kind}.capture.receipt.json`), true);
      if (!receipt) fail('CLAIM_CONSUMED_NO_RESULT');
      const captured = await readBoundLocalFile(capturePath, {
        code: 'REMOTE_CAPTURE_RECOVERY', expectedSha256: claim.expected_sha256, modes: [0o600],
      });
      const captureIdentitySha256 = physicalIdentitySha256(captured.metadata);
      const remoteCommandSha256 = sha256(Buffer.from(buildRemoteCatCommand(authority.remote[`${kind}_path`])));
      validateRemoteCaptureReceipt(receipt, {
        kind, claim, captureSha256: sha256(captured.bytes), captureIdentitySha256, remoteCommandSha256,
      });
      captures.set(kind, Buffer.from(captured.bytes));
      return {
        captureSha256: receipt.capture_sha256,
        captureIdentitySha256: receipt.capture_identity_sha256,
        remoteCommandSha256: receipt.remote_command_sha256,
        descriptorRead: true, bytes: receipt.bytes, exit: 0, stderrClass: 'EMPTY',
        startedAt: receipt.started_at, finishedAt: receipt.finished_at,
      };
    },
    publishLocal: async ({ readResults, simulator, ssh, claimCreated }) => {
      if (claimCreated !== true) fail('CLAIM_CONSUMED_NO_RESULT');
      const loadCapture = async (kind) => {
        if (captures.has(kind)) return captures.get(kind);
        const expected = context.remote[`${kind}_sha256`];
        return readExactOperationalFile(path.join(capturesRoot, `${kind}.capture`), expected, 'LOCAL_PUBLICATION');
      };
      const configBytes = await loadCapture('config');
      const credentialBytes = await loadCapture('credential');
      const receiptBytes = await loadCapture('receipt');
      if (!configBytes || !credentialBytes || !receiptBytes) fail('LOCAL_PUBLICATION');
      validateRemoteBundleSemantics({ context, configBytes, credentialBytes, receiptBytes });
      const bundleParent = path.join(homedir(), '.config/agentempp/ci3/bundles', context.authority.commit);
      await mkdir(bundleParent, { recursive: true, mode: 0o700 });
      await ensurePrivateDirectoryChain(homedir(), bundleParent);
      const finalRoot = path.join(bundleParent, context.generations.remote);
      const stagingRoot = path.join(bundleParent, `.staging-${context.generations.remote}`);
      if (await lstat(finalRoot).catch(() => null) || await lstat(stagingRoot).catch(() => null)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
      await mkdir(stagingRoot, { mode: 0o700 });
      const stagingObserved = await lstat(stagingRoot);
      if (!stagingObserved.isDirectory() || stagingObserved.isSymbolicLink()
          || (stagingObserved.mode & 0o777) !== 0o700
          || stagingObserved.uid !== process.getuid() || stagingObserved.gid !== process.getgid()) fail('LOCAL_PUBLICATION');
      const stageFile = async (name, bytes) => {
        const target = path.join(stagingRoot, name);
        const existing = await lstat(target).catch(() => null);
        if (existing) {
          if (!existing.isFile() || existing.isSymbolicLink() || existing.nlink !== 1
              || (existing.mode & 0o777) !== 0o600
              || existing.uid !== process.getuid() || existing.gid !== process.getgid()) fail('LOCAL_DIVERGENT_EXISTING');
          const current = await readExactOperationalFile(target, sha256(bytes), 'LOCAL_DIVERGENT_EXISTING');
          if (!current.equals(bytes)) fail('LOCAL_DIVERGENT_EXISTING');
          return;
        }
        const handle = await open(target, FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW, 0o600);
        try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
      };
      await stageFile('mobile-staging-config.json', configBytes);
      await stageFile('synthetic-patient.credentials.json', credentialBytes);
      const bootstrapClaim = await journal.loadClaim('bootstrap');
      const readClaims = [];
      for (const kind of ['receipt', 'config', 'credential']) readClaims.push(await journal.loadClaim(kind));
      if (!bootstrapClaim || readClaims.some((claim) => !claim) || readResults.length !== 3) fail('LOCAL_PUBLICATION');
      const localReceipt = canonicalJson({
        schema_version: 1, purpose: 'CI3_LOCAL_BRIDGE_RECEIPT_V1', authority_sha: context.authority.commit,
        components: context.authority.components, generations: context.generations,
        bootstrap_claim_sha256: sha256(canonicalJson(bootstrapClaim)),
        read_claim_chain_sha256: sha256(canonicalJson(readClaims)),
        read_result_chain_sha256: sha256(canonicalJson(readResults)),
        remote_receipt_sha256: sha256(receiptBytes), config_sha256: sha256(configBytes),
        credential_sha256: sha256(credentialBytes),
        simulator_gate_sha256: sha256(canonicalJson(simulator.receipt)),
        ssh_provenance_sha256: sha256(canonicalJson(ssh.provenance)),
        terminal_scan_ids: TERMINAL_SCAN_IDS, terminal_state: 'PENDING_INSTALL_AND_SCANS', raw_values: false,
      });
      await stageFile('local-bridge.receipt.json', localReceipt);
      await fsyncDirectory(stagingRoot);
      const promotionHelper = await prepareWriterBinary({
        operationStateRoot,
        sourcePath: path.join(path.dirname(SCRIPT_PATH), 'ci3-terminal-anchor-writer.swift'),
        sourceSha256: context.authority.components.writer.sha256,
        terminalGenerationId: context.generations.terminal,
      });
      await promoteDirectoryNoReplace({
        stagingRoot, finalRoot,
        exclusiveRename: async ({ source, destination }) => {
          const promoted = runFixedCommand(promotionHelper.binaryPath, ['--promote-directory', source, destination]);
          if (promoted.stderr.length !== 0 || promoted.stdout.toString('utf8') !== 'PROMOTE PASS\n') fail('LOCAL_PUBLICATION_RACE');
        },
      });
      return { local_bundle_sha256: sha256(localReceipt), receipt_sha256: sha256(localReceipt), root: finalRoot, config_sha256: sha256(configBytes), credential_sha256: sha256(credentialBytes) };
    },
    installSimulator: async ({ local, claimCreated }) => {
      if (claimCreated !== true) fail('CLAIM_CONSUMED_NO_RESULT');
      await readExactOperationalFile(
        path.join(local.root, 'local-bridge.receipt.json'),
        local.receipt_sha256 ?? local.local_bundle_sha256,
        'LOCAL_UNPUBLISHED',
      );
      const containerPath = simulatorContainer.path ?? await getContainer();
      const destinationRoot = path.join(containerPath, 'Library/Application Support/Agentempp');
      await mkdir(destinationRoot, { recursive: true, mode: 0o700 });
      const installClaim = {
        schema_version: 1, purpose: 'CI3_SIMULATOR_INSTALL_CLAIM_V1', authority_sha: context.authority.commit,
        controller_generation_id: context.generations.controller,
        simulator_generation_id: context.generations.simulator,
        local_bundle_sha256: local.local_bundle_sha256, attempt: 1, retry: false, raw_values: false,
      };
      const installClaimPath = path.join(operationStateRoot, 'simulator-install.claim.json');
      const priorInstallClaim = await readPrivateJson(installClaimPath, true);
      if (priorInstallClaim) fail('CLAIM_CONSUMED_NO_RESULT');
      for (const name of ['mobile-staging-config.json', 'synthetic-patient.credentials.json']) {
        if (await lstat(path.join(destinationRoot, name)).catch(() => null)) fail('REJECT_UNCLAIMED_EXISTING_STATE');
      }
      if (priorInstallClaim && !canonicalJson(priorInstallClaim).equals(canonicalJson(installClaim))) fail('SIMULATOR_INSTALL');
      await writeOnceJson(installClaimPath, installClaim);
      const fileReceipts = [];
      for (const name of ['mobile-staging-config.json', 'synthetic-patient.credentials.json']) {
        const sourcePath = path.join(local.root, name);
        const destination = path.join(destinationRoot, name);
        const sourceExpectedSha = name === 'mobile-staging-config.json' ? local.config_sha256 : local.credential_sha256;
        const sourceBytes = await readExactOperationalFile(sourcePath, sourceExpectedSha, 'SIMULATOR_INSTALL');
        const preexisting = await lstat(destination).catch(() => null);
        if (!preexisting) {
          const installed = runFixedCommand(INSTALL_PATH, ['-m', '0600', sourcePath, destination]);
          if (installed.stdout.length || installed.stderr.length) fail('SIMULATOR_INSTALL');
        }
        const observed = await lstat(destination, { bigint: true });
        if (!observed.isFile() || observed.isSymbolicLink() || observed.nlink !== 1n || (observed.mode & 0o777n) !== 0o600n) fail('SIMULATOR_INSTALL');
        const readback = await readExactOperationalFile(destination, sha256(sourceBytes), 'SIMULATOR_INSTALL');
        if (!readback.equals(sourceBytes)) fail('SIMULATOR_INSTALL');
        const physical = metadataFromBigIntStat(observed, 'SIMULATOR_INSTALL').metadata;
        fileReceipts.push({
          name_sha256: sha256(Buffer.from(name)), sha256: sha256(readback), ...physical,
        });
      }
      const receipt = canonicalJson({
        schema_version: 1, purpose: 'CI3_SIMULATOR_INSTALL_RECEIPT_V1', authority_sha: context.authority.commit,
        controller_generation_id: context.generations.controller,
        simulator_generation_id: context.generations.simulator,
        local_bundle_sha256: local.local_bundle_sha256, install_claim_sha256: sha256(canonicalJson(installClaim)),
        install_executable_sha256: sha256(await readFile(INSTALL_PATH)), files: fileReceipts, raw_values: false,
      });
      const receiptPath = path.join(operationStateRoot, 'simulator-install.receipt.json');
      await writeOnceBytes(receiptPath, receipt);
      const readback = await readBoundLocalFile(receiptPath, { code: 'SIMULATOR_INSTALL', expectedSha256: sha256(receipt) });
      return {
        install_receipt_sha256: sha256(readback.bytes), install_receipt_path: receiptPath,
        install_receipt_metadata: readback.metadata, destination_root: destinationRoot,
      };
    },
    removeSimulatorCredential: async ({ installed, recovery = false }) => {
      if (!recovery) {
        const launched = runFixedCommand(XCRUN_PATH, ['simctl', 'launch', authority.simulator.device_udid, BUNDLE_ID]);
        if (launched.stderr.length !== 0) fail('SIMULATOR_INSTALL');
      }
      const credentialPath = path.join(installed.destination_root, 'synthetic-patient.credentials.json');
      await lstat(credentialPath).then(() => fail('SIMULATOR_CREDENTIAL_NOT_REMOVED'), (error) => { if (error?.code !== 'ENOENT') throw error; });
      return { removed: true, removal_proof_sha256: sha256(canonicalJson({ absent: true })) };
    },
    scan: async ({ installed, local, readResults, simulator, ssh, recovery = false }) => {
      const readClaims = [];
      for (const kind of ['receipt', 'config', 'credential']) {
        const claim = await journal.loadClaim(kind);
        if (!claim) fail('TERMINAL_EVIDENCE');
        readClaims.push(claim);
      }
      const scanContracts = TERMINAL_SCAN_IDS.map((id) => structuredClone(authority.scans[id]));
      const inputManifest = canonicalJson({
        schema_version: 1, purpose: 'CI3_TERMINAL_INPUT_MANIFEST_V1',
        authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
        local_bundle_sha256: local.local_bundle_sha256, simulator_install_sha256: installed.install_receipt_sha256,
        terminal_generation_id: context.generations.terminal,
        read_commands: readClaims.map((claim, index) => ({
          kind: claim.kind, expected_path_sha256: claim.expected_path_sha256,
          expected_sha256: claim.expected_sha256, capture_sha256: readResults[index].capture_sha256,
          remote_command_sha256: readResults[index].remote_command_sha256,
        })),
        scan_contracts: scanContracts, scan_ids: TERMINAL_SCAN_IDS, raw_values: false,
      });
      const inputManifestPath = path.join(terminalEvidenceRoot, 'input-manifest.json');
      await writeOnceBytes(inputManifestPath, inputManifest);
      const authorityManifestPath = path.join(terminalEvidenceRoot, 'authority-manifest.json');
      const authorityManifestSnapshot = await readBoundLocalFile(
        path.join(path.dirname(SCRIPT_PATH), 'authority-manifest.v1'),
        { code: 'AUTHORITY_MANIFEST', expectedSha256: context.authority.manifest_sha256 },
      );
      const literalAuthorityManifest = parseAuthorityManifestBytes(authorityManifestSnapshot.bytes, context.authority.components);
      await writeOnceBytes(authorityManifestPath, canonicalJson(literalAuthorityManifest));
      const launchAttestationPath = path.join(terminalEvidenceRoot, 'launch-attestation.json');
      await writeOnceBytes(launchAttestationPath, canonicalJson(launchAttestation));
      const sourceSnapshotPath = path.join(path.dirname(SCRIPT_PATH), 'ci3-terminal-anchor-writer.swift');
      const sourceSnapshot = await readBoundLocalFile(sourceSnapshotPath, {
        code: 'TERMINAL_WRITER', expectedSha256: context.authority.components.writer.sha256,
      });
      const writerSourcePath = path.join(terminalEvidenceRoot, 'writer-source.swift');
      await writeOnceBytes(writerSourcePath, sourceSnapshot.bytes);
      const receipts = [];
      const surfaceRoot = path.join(terminalEvidenceRoot, 'final-surfaces', context.generations.controller);
      if (!recovery) {
        await ensurePrivateDirectory(path.join(terminalEvidenceRoot, 'final-surfaces'));
        await ensurePrivateDirectory(surfaceRoot);
      }
      if (recovery) {
        for (const id of TERMINAL_SCAN_IDS) {
          const receipt = await readPrivateJson(path.join(terminalEvidenceRoot, `scan-${id}.json`), true);
          if (!receipt) fail('PHASE_RECOVERY_DIVERGENCE');
          validateScanReceipt(receipt, id);
          for (const observation of receipt.input_observations) {
            const reobserved = await readBoundLocalFile(observation.path, { code: 'TERMINAL_SCAN_INPUT', expectedSha256: observation.sha256, modes: [0o600] });
            if (sha256(reobserved.bytes) !== observation.sha256
                || !canonicalJson(reobserved.metadata).equals(canonicalJson(observation.metadata))) {
              fail('TERMINAL_SCAN_INPUT');
            }
            let surface;
            try { surface = JSON.parse(reobserved.bytes.toString('utf8')); } catch { fail('TERMINAL_SCAN_INPUT'); }
            const currentSource = await observeTerminalScanSource({
              scanId: id, root: terminalEvidenceRoot,
              sourcePath: id === 'xcresult'
                ? path.join(terminalEvidenceRoot, 'operational-results', `${context.generations.simulator}.xcresult`)
                : null,
            });
            if (!surface.source_observation
                || !canonicalJson(currentSource).equals(canonicalJson(surface.source_observation))) fail('TERMINAL_SCAN_INPUT');
          }
          receipts.push(receipt);
        }
        return receipts;
      }
      const completedEvidencePhases = CONTROLLER_EVIDENCE_PHASES.filter((phase) => phase !== 'RUN_SCANS');
      const historyPaths = [
        journal.paths.claim('bootstrap'),
        ...['receipt', 'config', 'credential'].flatMap((kind) => [journal.paths.claim(kind), journal.paths.result(kind)]),
      ];
      const terminalLogPaths = [];
      for (const phase of completedEvidencePhases) {
        const claim = await journal.loadPhaseClaim(phase);
        const result = await journal.loadPhaseResult(phase);
        const event = await journal.load(phase);
        if (!claim || !result || !event) fail('TERMINAL_SCAN_SOURCE');
        historyPaths.push(
          journal.paths.phaseClaim(phase), journal.paths.phaseReceipt(phase), journal.paths.phaseResult(phase),
        );
        terminalLogPaths.push(journal.paths.event(phase));
      }
      const attachmentPaths = [
        inputManifestPath, authorityManifestPath, launchAttestationPath, writerSourcePath,
        path.join(local.root, 'local-bridge.receipt.json'), installed.install_receipt_path,
      ];
      const operationalResultRoot = path.join(terminalEvidenceRoot, 'operational-results');
      await ensurePrivateDirectory(operationalResultRoot);
      const xcresultPath = path.join(operationalResultRoot, `${context.generations.simulator}.xcresult`);
      const actualSurfaces = await collectActualTerminalSurfaces({
        argv: [...process.argv], historyPaths, terminalLogPaths, attachmentPaths, xcresultPath,
        runtime: {
          executable: process.execPath, exec_argv: [...process.execArgv],
          environment: sanitizeTerminalRuntimeEnvironment(process.env),
        },
      });
      for (const id of TERMINAL_SCAN_IDS) {
        const currentBytes = actualSurfaces[id] ?? Buffer.alloc(0);
        if (scanTerminalSurface(id, currentBytes).total !== 0) fail('TERMINAL_SCAN_MATCH');
      }
      const sourceObservations = await materializeTerminalScanSources({
        root: terminalEvidenceRoot,
        records: {
          argv: actualSurfaces.argv,
          history: actualSurfaces.history,
          'terminal-log': actualSurfaces['terminal-log'],
          attachment: actualSurfaces.attachment,
          runtime: actualSurfaces.runtime,
        },
        sourcePaths: { xcresult: xcresultPath },
      });
      for (const id of TERMINAL_SCAN_IDS) {
        const startedAt = new Date().toISOString();
        const digests = [];
        const observations = [];
        const counters = { secret: 0, pii: 0, jwt: 0, token: 0, raw_destination: 0 };
        const descriptor = authority.scans[id];
        const sourceObservation = sourceObservations[id];
        const sourceBytes = sourceObservation.state === 'PRESENT'
          ? (await readBoundLocalFile(sourceObservation.path, {
            code: 'TERMINAL_SCAN_INPUT', expectedSha256: sourceObservation.content_sha256, modes: [0o600],
          })).bytes
          : Buffer.alloc(0);
        const scanResult = scanTerminalSurface(id, sourceBytes);
        if (scanResult.total !== 0) fail('TERMINAL_SCAN_MATCH');
        const surfaceBytes = buildFinalScanSurfaceBytes({
          scanId: id, authoritySha: context.authority.commit,
          controllerGenerationId: context.generations.controller,
          terminalGenerationId: context.generations.terminal,
          sourceRoots: [{
            role: descriptor.source_role, sha256: sha256(sourceBytes),
            identity_sha256: sourceObservation.identity_sha256 ?? sourceObservation.absence_observation_sha256,
          }],
          sourceBytes, sourceObservation,
        });
        const surfacePath = path.join(surfaceRoot, `${id}.surface`);
        await writeOnceBytes(surfacePath, surfaceBytes);
        const observed = await readBoundLocalFile(surfacePath, { code: 'TERMINAL_SCAN_INPUT', expectedSha256: sha256(surfaceBytes), modes: [0o600] });
        digests.push(sha256(sourceBytes));
        observations.push({ path: surfacePath, path_sha256: sha256(Buffer.from(surfacePath)), sha256: sha256(observed.bytes), metadata: observed.metadata });
        for (const key of Object.keys(counters)) counters[key] += scanResult.counters[key];
        const reobserved = await readBoundLocalFile(surfacePath, { code: 'TERMINAL_SCAN_INPUT', expectedSha256: sha256(surfaceBytes), modes: [0o600] });
        if (sha256(reobserved.bytes) !== observations[0].sha256
            || !canonicalJson(reobserved.metadata).equals(canonicalJson(observations[0].metadata))) fail('TERMINAL_SCAN_INPUT');
        const finishedAt = new Date().toISOString();
        const receipt = {
          schema_version: 1, purpose: 'CI3_TERMINAL_SCAN_RECEIPT_V1', scan_id: id,
          authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
          remote_generation_id: context.generations.remote, local_bundle_sha256: local.local_bundle_sha256,
          simulator_generation_id: context.generations.simulator,
          terminal_generation_id: context.generations.terminal,
          simulator_install_sha256: installed.install_receipt_sha256,
          worktree_diff_sha256: authority.worktree.diff_sha256,
          input_manifest_sha256: sha256(inputManifest), input_observations: observations,
          tool_sha256: descriptor.tool_sha256,
          command_sha256: sha256(canonicalJson({
            scan_id: id, collector_version: descriptor.collector_version,
            contract_sha256: descriptor.contract_sha256, source_role: descriptor.source_role,
            tool_sha256: descriptor.tool_sha256,
          })),
          scanner_schema_sha256: scannerSchemaSha256(id), counters,
          started_at: startedAt, finished_at: finishedAt, result: Object.values(counters).every((value) => value === 0) ? 'CLEAN' : 'MATCH',
          match_count: Object.values(counters).reduce((sum, value) => sum + value, 0),
          output_sha256: sha256(canonicalJson(digests.map((value) => ({ byte_length: sourceBytes.length, sha256: value })))),
          redaction: true, input_stable_after_scan: true,
        };
        validateScanReceipt(receipt, id);
        await writeOnceJson(path.join(terminalEvidenceRoot, `scan-${id}.json`), receipt);
        receipts.push(receipt);
      }
      return receipts;
    },
    invokeWriter: async ({ local, installed, readResults, scans, recovery = false }) => {
      const expectedAnchorPath = path.join(
        '/Library/Application Support/Agentempp/ci3-terminal-authority',
        context.authority.commit, context.generations.terminal, 'pre-anchor.json',
      );
      const expectedSettlementPath = path.join(
        '/Library/Application Support/Agentempp/ci3-terminal-authority',
        context.authority.commit, context.generations.terminal, 'terminal-settlement.json',
      );
      const expectedFinalScanPath = path.join(path.dirname(expectedSettlementPath), 'terminal-final-scan.json');
      const expectedCompletePath = path.join(path.dirname(expectedSettlementPath), 'complete-result.json');
      const expectedCompleteFinalScanPath = path.join(path.dirname(expectedSettlementPath), 'complete-final-scan.json');
      const readValidatedPrivilegedMarker = async () => {
        const observed = await readTerminalPassMarker();
        if (observed === null) return null;
        validatePrivilegedTerminalPassCorpus({
          marker: observed.marker, context, paths: observed.paths, ...observed.inputs,
        });
        let settlement;
        let complete;
        try {
          settlement = JSON.parse(observed.inputs.settlementBytes.toString('utf8'));
          complete = JSON.parse(observed.inputs.completeBytes.toString('utf8'));
        } catch { fail('TERMINAL_SETTLEMENT'); }
        validateTerminalSettlementReceipt(settlement);
        validateTerminalCompleteResult(complete, {
          settlementBytes: observed.inputs.settlementBytes,
          finalScanBytes: await readRootImmutableFile(
            expectedFinalScanPath, null, 0o444, 'TERMINAL_COMPLETE',
          ).then((value) => value.bytes),
        });
        validateTerminalCompleteFinalScan(
          JSON.parse(observed.inputs.completeFinalScanBytes.toString('utf8')),
          observed.inputs.completeBytes,
        );
        const anchor = await readRootImmutableFile(expectedAnchorPath, null, 0o444, 'TERMINAL_ANCHOR');
        if (settlement.pre_anchor_sha256 !== sha256(anchor.bytes)
            || !canonicalJson(settlement.generations).equals(canonicalJson(context.generations))) {
          fail('TERMINAL_SETTLEMENT');
        }
        return {
          pre_anchor_sha256: sha256(anchor.bytes), settlement,
          complete_sha256: sha256(observed.inputs.completeBytes),
          marker_sha256: observed.markerSha256, marker_verified: true,
          terminal_state: 'TERMINAL_PASS',
        };
      };
      const invokeAuthorizedWriterTransaction = async () => {
      const buildRoot = path.join(operationStateRoot, 'writer-build', context.generations.terminal);
      const candidateBinaryPath = path.join(buildRoot, 'ci3-terminal-anchor-writer');
      const manifest = await readBoundLocalFile(authority.writer.manifest_path, { code: 'TERMINAL_MANIFEST' });
      const candidateBinary = await readBoundLocalFile(candidateBinaryPath, { code: 'TERMINAL_WRITER', modes: [0o700] });
      const claimPath = path.join(path.dirname(authority.writer.manifest_path), 'privileged-anchor.claim.json');
      const claim = await readBoundLocalFile(claimPath, {
        code: 'STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY', modes: [0o600],
        allowedUids: [process.getuid(), 0], allowedGids: [process.getgid(), 0],
      });
      const authorityBytes = await readPrivilegedAuthorityFile(authority.writer.authority_path, null);
      const rootClaim = await readRootImmutableFile(
        path.join(path.dirname(authority.writer.authority_path), 'privileged-anchor.claim.json'),
        sha256(claim.bytes), 0o444, 'STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY',
      );
      if (!rootClaim.bytes.equals(claim.bytes)) fail('STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY');
      let authorityReceipt;
      let privilegedClaim;
      let terminalManifest;
      try {
        authorityReceipt = JSON.parse(authorityBytes.toString('utf8'));
        privilegedClaim = JSON.parse(claim.bytes.toString('utf8'));
        terminalManifest = JSON.parse(manifest.bytes.toString('utf8'));
      } catch { fail('STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY'); }
      const privilegedBinaryPath = privilegedWriterExecutablePath(context.authority.commit, context.generations.terminal);
      const privilegedBinary = await readRootImmutableFile(
        privilegedBinaryPath, authorityReceipt.writer_binary_sha256, 0o555,
        'STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY',
      );
      const signature = runFixedCommand('/usr/bin/codesign', ['-d', '-r-', privilegedBinaryPath]);
      const signatureSha256 = sha256(Buffer.concat([signature.stdout, signature.stderr]));
      validatePrivilegedWriterAuthorityReceipt(authorityReceipt, {
        authoritySha: context.authority.commit,
        terminalGenerationId: context.generations.terminal,
        terminalManifestSha256: sha256(manifest.bytes),
        writerSourceSha256: context.authority.components.writer.sha256,
        writerBinarySha256: sha256(privilegedBinary.bytes),
        writerSignatureSha256: signatureSha256,
        privilegedClaimSha256: sha256(claim.bytes),
        authorityPathSha256: sha256(Buffer.from(authority.writer.authority_path)),
        anchorPathSha256: sha256(Buffer.from(expectedAnchorPath)),
        terminalManifestPathSha256: sha256(Buffer.from(authority.writer.manifest_path)),
        writerExecutablePathSha256: sha256(Buffer.from(privilegedBinaryPath)),
        writerExecutableIdentitySha256: privilegedBinary.identity_sha256,
      });
      if (sha256(candidateBinary.bytes) !== sha256(privilegedBinary.bytes)) fail('STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY');
      exactKeys(privilegedClaim, [
        'anchor_path_sha256', 'attempt', 'authority_sha', 'file_mode', 'gid',
        'immutable_flag', 'normal_executor_authorized', 'purpose', 'retry',
        'schema_version', 'terminal_generation_id', 'terminal_manifest_sha256',
        'uid', 'writer_binary_sha256', 'writer_source_sha256',
      ], 'STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY');
      if (privilegedClaim.schema_version !== 1
          || privilegedClaim.purpose !== 'CI3_PRIVILEGED_TERMINAL_ANCHOR_CLAIM_V1'
          || privilegedClaim.authority_sha !== context.authority.commit
          || privilegedClaim.terminal_generation_id !== context.generations.terminal
          || privilegedClaim.terminal_manifest_sha256 !== sha256(manifest.bytes)
          || privilegedClaim.writer_source_sha256 !== context.authority.components.writer.sha256
          || privilegedClaim.writer_binary_sha256 !== sha256(privilegedBinary.bytes)
          || privilegedClaim.anchor_path_sha256 !== sha256(Buffer.from(expectedAnchorPath))
          || privilegedClaim.attempt !== 1 || privilegedClaim.retry !== false
          || privilegedClaim.uid !== 0 || privilegedClaim.gid !== 0
          || privilegedClaim.file_mode !== '0444' || privilegedClaim.immutable_flag !== 'UF_IMMUTABLE'
          || privilegedClaim.normal_executor_authorized !== false
          || terminalManifest.writer_source_sha256 !== context.authority.components.writer.sha256
          || terminalManifest.writer_binary_sha256 !== sha256(privilegedBinary.bytes)
          || terminalManifest.writer_signature_sha256 !== signatureSha256
          || terminalManifest.writer_authority_path_sha256 !== sha256(Buffer.from(authority.writer.authority_path))) {
        fail('STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY');
      }
      const appleScript = [
        'on run argv',
        'set cmd to quoted form of item 1 of argv',
        'repeat with i from 2 to count of argv',
        'set cmd to cmd & " " & quoted form of item i of argv',
        'end repeat',
        'do shell script cmd with administrator privileges',
        'end run',
      ].join('\n');
      const result = runFixedCommand('/usr/bin/osascript', [
        '-e', appleScript, '--', privilegedBinaryPath, '--write', authority.writer.manifest_path,
        authority.writer.authority_path,
        context.authority.commit, context.generations.remote, context.generations.controller,
        context.generations.simulator, context.generations.terminal,
      ]);
      if (result.stderr.length !== 0) fail('TERMINAL_WRITER');
      const match = result.stdout.toString('utf8').trim().match(/^WRITER_TRANSACTION PASS status=(?:CREATED|EXISTS_VERIFIED) pre_anchor_sha256=([a-f0-9]{64}) settlement_sha256=([a-f0-9]{64})$/);
      if (!match) fail('TERMINAL_WRITER');
      const settled = await readValidatedPrivilegedMarker();
      if (settled === null || settled.pre_anchor_sha256 !== match[1]
          || settled.settlement.settlement_sha256 !== match[2]) fail('TERMINAL_TAIL_AUTHORITY');
      return settled;
      };
      if (recovery) {
        const terminalRecovery = await runPrivilegedTerminalRecovery({
          recovery: true,
          observe: async () => {
            const settled = await readValidatedPrivilegedMarker();
            return settled === null
              ? {
                state: 'RECOVERABLE', marker_verified: false,
                terminal_state: 'PRE_TERMINAL_UNPUBLISHED',
              }
              : { state: 'SETTLED', ...settled };
          },
          waitForAuthorizedSupervisor: async () => {
            for (let attempt = 0; attempt < 300; attempt += 1) {
              if (await readValidatedPrivilegedMarker() !== null) {
                return { effect_executions: 0, admin_prompts: 0 };
              }
              await new Promise((resolve) => setTimeout(resolve, 100));
            }
            return { effect_executions: 0, admin_prompts: 0 };
          },
        });
        return {
          pre_anchor_sha256: terminalRecovery.pre_anchor_sha256,
          settlement: terminalRecovery.settlement,
          complete_sha256: terminalRecovery.complete_sha256,
          marker_sha256: terminalRecovery.marker_sha256,
          marker_verified: true, terminal_state: 'TERMINAL_PASS',
        };
      }
      return invokeAuthorizedWriterTransaction();
    },
    verifyAnchor: async ({ writer }) => {
      requireSha(writer.pre_anchor_sha256, 'TERMINAL_ANCHOR');
      const anchorPath = path.join('/Library/Application Support/Agentempp/ci3-terminal-authority', context.authority.commit, context.generations.terminal, 'pre-anchor.json');
      const anchor = await readRootImmutableFile(anchorPath, writer.pre_anchor_sha256, 0o444, 'TERMINAL_ANCHOR');
      const settlementPath = path.join('/Library/Application Support/Agentempp/ci3-terminal-authority', context.authority.commit, context.generations.terminal, 'terminal-settlement.json');
      const settlement = await readRootImmutableFile(settlementPath, writer.settlement?.settlement_sha256 ? null : null, 0o444, 'TERMINAL_SETTLEMENT');
      const finalScan = await readRootImmutableFile(path.join(path.dirname(settlementPath), 'terminal-final-scan.json'), null, 0o444, 'TERMINAL_COMPLETE');
      const complete = await readRootImmutableFile(path.join(path.dirname(settlementPath), 'complete-result.json'), writer.complete_sha256, 0o444, 'TERMINAL_COMPLETE');
      const completeFinalScan = await readRootImmutableFile(path.join(path.dirname(settlementPath), 'complete-final-scan.json'), null, 0o444, 'TERMINAL_COMPLETE');
      let settlementReceipt;
      let completeReceipt;
      try {
        settlementReceipt = JSON.parse(settlement.bytes.toString('utf8'));
        completeReceipt = JSON.parse(complete.bytes.toString('utf8'));
      } catch { fail('TERMINAL_SETTLEMENT'); }
      validateTerminalSettlementReceipt(settlementReceipt);
      validateTerminalCompleteResult(completeReceipt, { settlementBytes: settlement.bytes, finalScanBytes: finalScan.bytes });
      validateTerminalCompleteFinalScan(JSON.parse(completeFinalScan.bytes), complete.bytes);
      if (settlementReceipt.pre_anchor_sha256 !== writer.pre_anchor_sha256
          || settlementReceipt.settlement_sha256 !== writer.settlement?.settlement_sha256
          || sha256(complete.bytes) !== writer.complete_sha256) fail('TERMINAL_SETTLEMENT');
      return {
        verified: true, pre_anchor_sha256: writer.pre_anchor_sha256,
        anchor_identity_sha256: anchor.identity_sha256,
        terminal_settlement_sha256: settlementReceipt.settlement_sha256,
        terminal_complete_sha256: sha256(complete.bytes),
      };
    },
    settleTerminal: async ({ writer }) => {
      const code = 'TERMINAL_SETTLEMENT';
      const authorityReceipt = await readRootImmutableFile(authority.writer.authority_path, null, 0o444, code);
      let privilegedAuthority;
      try { privilegedAuthority = JSON.parse(authorityReceipt.bytes.toString('utf8')); } catch { fail(code); }
      if (privilegedAuthority.purpose !== 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1'
          || privilegedAuthority.authority_sha !== context.authority.commit
          || privilegedAuthority.terminal_generation_id !== context.generations.terminal
          || privilegedAuthority.normal_executor_authorized !== false) fail(code);
      const binaryPath = privilegedWriterExecutablePath(context.authority.commit, context.generations.terminal);
      const binary = await readRootImmutableFile(binaryPath, privilegedAuthority.writer_binary_sha256, 0o555, code);
      if (binary.identity_sha256 !== privilegedAuthority.writer_executable_identity_sha256) fail(code);
      const settlementPath = path.join(
        '/Library/Application Support/Agentempp/ci3-terminal-authority',
        context.authority.commit, context.generations.terminal, 'terminal-settlement.json',
      );
      const settlement = await readRootImmutableFile(settlementPath, null, 0o444, code);
      let receipt;
      try { receipt = JSON.parse(settlement.bytes.toString('utf8')); } catch { fail(code); }
      validateTerminalSettlementReceipt(receipt);
      const finalScan = await readRootImmutableFile(path.join(path.dirname(settlementPath), 'terminal-final-scan.json'), null, 0o444, code);
      const complete = await readRootImmutableFile(path.join(path.dirname(settlementPath), 'complete-result.json'), writer.complete_sha256, 0o444, code);
      const completeFinalScan = await readRootImmutableFile(path.join(path.dirname(settlementPath), 'complete-final-scan.json'), null, 0o444, code);
      let completeReceipt;
      try { completeReceipt = JSON.parse(complete.bytes.toString('utf8')); } catch { fail(code); }
      validateTerminalCompleteResult(completeReceipt, { settlementBytes: settlement.bytes, finalScanBytes: finalScan.bytes });
      validateTerminalCompleteFinalScan(JSON.parse(completeFinalScan.bytes), complete.bytes);
      const manifestRoot = await readBoundLocalFile(authority.writer.manifest_path, { code, modes: [0o600] });
      let terminalManifest;
      try { terminalManifest = JSON.parse(manifestRoot.bytes.toString('utf8')); } catch { fail(code); }
      const contractsSha256 = sha256(canonicalJson(terminalManifest.terminal_settlement_contracts));
      const phaseRoot = path.join(path.dirname(settlementPath), 'terminal-phases');
      const phaseRoots = [];
      let predecessor = terminalManifest.terminal_settlement_contracts?.[0]?.predecessor_contract_sha256;
      for (let index = 0; index < TERMINAL_SETTLEMENT_PHASES.length; index += 1) {
        const phase = TERMINAL_SETTLEMENT_PHASES[index];
        const prefix = phase.toLowerCase().replaceAll('_', '-');
        const objects = {};
        const roots = {};
        for (const kind of ['claim', 'receipt', 'result']) {
          const item = await readRootImmutableFile(path.join(phaseRoot, `${prefix}.${kind}.json`), null, 0o444, code);
          try { objects[kind] = JSON.parse(item.bytes.toString('utf8')); } catch { fail(code); }
          roots[`${kind}_sha256`] = sha256(item.bytes);
        }
        const { claim, receipt: phaseReceipt, result: phaseResult } = objects;
        exactKeys(claim, ['attempt', 'authority_sha', 'contract_sha256', 'controller_generation_id', 'phase', 'predecessor_result_sha256', 'purpose', 'raw_values', 'retry', 'schema_version'], code);
        exactKeys(phaseReceipt, ['claim_sha256', 'observation', 'phase', 'purpose', 'raw_values', 'result', 'result_sha256', 'schema_version'], code);
        exactKeys(phaseResult, ['claim_sha256', 'phase', 'physical_observation_sha256', 'purpose', 'raw_values', 'receipt_sha256', 'schema_version', 'terminal_state'], code);
        const contract = terminalManifest.terminal_settlement_contracts[index];
        if (claim.schema_version !== 1 || claim.purpose !== 'CI3_MAC_PHASE_CLAIM_V1'
            || claim.phase !== phase || claim.authority_sha !== context.authority.commit
            || claim.controller_generation_id !== context.generations.controller
            || claim.predecessor_result_sha256 !== predecessor
            || claim.contract_sha256 !== sha256(canonicalJson(contract))
            || claim.attempt !== 1 || claim.retry !== false || claim.raw_values !== false
            || phaseReceipt.claim_sha256 !== roots.claim_sha256
            || phaseReceipt.result_sha256 !== sha256(canonicalJson(phaseReceipt.result))
            || phaseReceipt.phase !== phase || phaseReceipt.raw_values !== false
            || phaseResult.claim_sha256 !== roots.claim_sha256
            || phaseResult.receipt_sha256 !== roots.receipt_sha256
            || phaseResult.physical_observation_sha256 !== phaseReceipt.observation?.observation_sha256
            || phaseResult.phase !== phase || phaseResult.terminal_state !== 'PHASE_SETTLED'
            || phaseResult.raw_values !== false) fail(code);
        validatePhysicalEffectObservation(phaseReceipt.observation, phase);
        for (const target of phaseReceipt.observation.targets) {
          if (target.state !== 'PRESENT') fail(code);
          const reopened = await readRootImmutableFile(target.path, target.sha256, target.metadata.mode, code);
          if (reopened.identity_sha256 !== target.identity_sha256
              || !canonicalJson(reopened.metadata).equals(canonicalJson(target.metadata))) fail(code);
        }
        const expectedTriple = phase === 'INVOKE_WRITER' ? receipt.invoke_writer : receipt.verify_anchor;
        if (!canonicalJson(expectedTriple).equals(canonicalJson(roots))) fail(code);
        phaseRoots.push({ phase, ...roots });
        predecessor = roots.result_sha256;
      }
      if (receipt.settlement_sha256 !== writer.settlement?.settlement_sha256
          || receipt.pre_anchor_sha256 !== writer.pre_anchor_sha256
          || receipt.settlement_authority_sha256 !== sha256(authorityReceipt.bytes)) fail(code);
      if (!canonicalJson(receipt.generations).equals(canonicalJson(context.generations))
          || receipt.terminal_settlement_contracts_sha256 !== contractsSha256
          || receipt.terminal_phase_graph_sha256 !== sha256(canonicalJson(phaseRoots))) fail(code);
      return receipt;
    },
  };
  return {
    adapters, context, journal,
    terminalAuthority: { context, paths: terminalPassPaths, readMarker: readTerminalPassMarker },
  };
}

export async function createOperationalTerminalTailAdapter({ runtime, emit = null } = {}) {
  if (!isPlainObject(runtime) || !isPlainObject(runtime.context) || !isPlainObject(runtime.journal)
      || !isPlainObject(runtime.terminalAuthority)
      || typeof runtime.terminalAuthority.readMarker !== 'function') fail('TERMINAL_TAIL_AUTHORITY');
  const output = emit ?? ((bytes) => new Promise((resolve, reject) => {
    process.stdout.write(bytes, (error) => (error ? reject(error) : resolve()));
  }));
  if (typeof output !== 'function') fail('TERMINAL_TAIL');
  return {
    terminalizeTail: async () => {
      const observed = await runtime.terminalAuthority.readMarker();
      if (observed === null) fail('STOP_PRE_AUTHORITY');
      validatePrivilegedTerminalPassCorpus({
        marker: observed.marker, context: runtime.context,
        paths: observed.paths, ...observed.inputs,
      });
      await output(observed.inputs.stdoutBytes);
      return observed.marker;
    },
  };
}

export function sanitizeError(error) {
  const code = typeof error?.code === 'string' && /^[A-Z0-9_]+$/.test(error.code) ? error.code : 'UNEXPECTED';
  return `ERROR ${code}`;
}

async function main() {
  try {
    const mode = parseControllerMode(process.argv.slice(2));
    let publisher0Boundary = null;
    if (mode === '--self-test') {
      const attestationPath = path.join(path.dirname(SCRIPT_PATH), 'launch-attestation.json');
      try {
        validateLaunchAttestation(JSON.parse(await readFile(attestationPath, 'utf8')));
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error;
      }
      const outcome = await runSyntheticProtocol({
        scenarioId: process.env.CI3_SYNTHETIC_E2E_SCENARIO ?? null,
        scenarioSha256: process.env.CI3_SYNTHETIC_SCENARIO_SHA256 ?? null,
      });
      if (process.env.CI3_SYNTHETIC_E2E_ROOT) {
        const receipt = await runSyntheticIntegratedE2E({
          scenarioId: process.env.CI3_SYNTHETIC_E2E_SCENARIO,
          scenarioSha256: process.env.CI3_SYNTHETIC_SCENARIO_SHA256,
          outcome,
        });
        process.stdout.write(`CONTROLLER_SELF_TEST PASS checks=${outcome.journal_records} network_calls=0 privilege_prompts=0 integrated_e2e=${receipt.controller_state} writer_mode=${receipt.writer_mode} pre_anchor=${receipt.pre_anchor_state} terminal_settlement=${receipt.terminal_state}\n`);
      } else {
        process.stdout.write(`CONTROLLER_SELF_TEST PASS checks=${outcome.journal_records} network_calls=0 privilege_prompts=0\n`);
      }
      return;
    }
    if (mode === 'publish-vps-operation-authority-pass') publisher0Boundary = await assertPublisher0FixedProcessBoundary();
    // All operational modes require the sibling Git-bound launch attestation.
    // Absence fails before simulator, SSH, secrets, or privilege.
    const attestationPath = path.join(path.dirname(SCRIPT_PATH), 'launch-attestation.json');
    let attestation;
    try {
      attestation = JSON.parse(await readFile(attestationPath, 'utf8'));
    } catch {
      fail('LAUNCHER_REQUIRED');
    }
    validateLaunchAttestation(attestation);
    if (attestation.authority_parent !== AUTHORITY_PARENT
        || attestation.authority_subject_sha256 !== sha256(Buffer.from(AUTHORITY_SUBJECT))) fail('LAUNCHER_REQUIRED');
    const runtime = mode === 'publish-vps-operation-authority-pass'
      ? { adapters: await createVpsOperationAuthorityPassPublisher({ launchAttestation: attestation, bootstrapBoundary: publisher0Boundary }) }
      : mode === 'publish-operation-authority'
        ? { adapters: await createOperationAuthorityPublisher({ launchAttestation: attestation }) }
        : await createOperationalRuntime({ launchAttestation: attestation });
    if (mode === '--terminalize-tail') {
      const tailAdapters = await createOperationalTerminalTailAdapter({ runtime });
      await dispatchControllerMode({ mode, adapters: tailAdapters });
      return;
    }
    const outcome = await dispatchControllerMode({ mode, ...runtime });
    if (outcome.state === 'PRE_TERMINAL_UNPUBLISHED') {
      process.stdout.write(`CONTROLLER ${mode.toUpperCase()} PRE_TERMINAL state=${outcome.state} raw_values=false\n`);
    } else {
      process.stdout.write(`CONTROLLER ${mode.toUpperCase()} PASS state=${outcome.state} raw_values=false\n`);
    }
  } catch (error) {
    process.stderr.write(`${sanitizeError(error)}\n`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.basename(process.argv[1]) === path.basename(SCRIPT_PATH)) await main();
