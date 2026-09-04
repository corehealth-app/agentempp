import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { generateKeyPairSync } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { chmod, lstat, mkdir, mkdtemp, open, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import * as subject from './ci3-external-publisher-chain.mjs';
import * as controllerContract from './ci3-bridge-controller.mjs';

const CHAIN_SCRIPT = fileURLToPath(new URL('./ci3-external-publisher-chain.mjs', import.meta.url));
const INSTALLER_SOURCE = path.join(path.dirname(CHAIN_SCRIPT), 'ci3-publisher1-bootstrap-installer.swift');
const WRITER_SOURCE = path.join(path.dirname(CHAIN_SCRIPT), 'ci3-terminal-anchor-writer.swift');

const H40 = 'a'.repeat(40);
const H64 = 'b'.repeat(64);
const CONTROLLER_GENERATION = `controller-${'c'.repeat(64)}`;
const REMOTE_GENERATION = `remote-${'d'.repeat(64)}`;

function productionFrozenInputBinding() {
  return {
    schema_version: 1,
    purpose: 'CI3_PRODUCTION_FROZEN_INPUT_CONSUMER_BINDING_V1',
    constructor_claim_sha256: '1'.repeat(64),
    corpus_sha256: '2'.repeat(64),
    authorized_producer_matrix_sha256: '3'.repeat(64),
    materialized_input_matrix_sha256: '4'.repeat(64),
    oob_receipt_sha256: '5'.repeat(64),
    authenticated_ssh_receipt_sha256: '6'.repeat(64),
    vps_node_reference_sha256: '7'.repeat(64),
    mac_node_capsule_receipt_sha256: '8'.repeat(64),
    requirements_total: 53,
    requirements_verified: 53,
    vps_runtime_role: 'VPS_BOOTSTRAP_NODE_RUNTIME',
    mac_runtime_role: 'MAC_EXECUTOR_NODE_RUNTIME',
    causal_order_sha256: subject.sha256(subject.canonicalJson(subject.PRODUCTION_FROZEN_INPUT_ORDER)),
    raw_values: false,
  };
}

test('[PRODUCTION-CONSUMER-1-RED/GREEN] external Publisher boundary accepts the exact 53/53 corpus binding and rejects topology/order drift', () => {
  const valid = productionFrozenInputBinding();
  assert.equal(subject.validateProductionFrozenInputConsumerBinding(valid), valid);
  for (const mutate of [
    (value) => { value.requirements_verified = 52; },
    (value) => { value.mac_runtime_role = 'VPS_BOOTSTRAP_NODE_RUNTIME'; },
    (value) => { value.vps_runtime_role = 'MAC_EXECUTOR_NODE_RUNTIME'; },
    (value) => { value.causal_order_sha256 = 'f'.repeat(64); },
  ]) {
    const changed = structuredClone(valid);
    mutate(changed);
    assert.throws(
      () => subject.validateProductionFrozenInputConsumerBinding(changed),
      (error) => error?.code === 'STOP_PRE_AUTHORITY',
    );
  }
});

function capsuleInstallTopology() {
  const authority = H40;
  const image = { destination: 'lib/0123456789abcdef-libx.dylib', sha256: '9'.repeat(64) };
  const manifest = {
    schema_version: 4, purpose: 'MAC_RELOCATABLE_NODE_CAPSULE_V4', authority,
    generation: 'capsule-v4', role: 'MAC_EXECUTOR_NODE_RUNTIME',
    predecessor_authority: '85a9ebba88722915df56583d29defc253016a5f9', predecessor_generation: 'capsule-v3',
    predecessor_status: 'FAILED_PARTIAL_PRESERVED', predecessor_attempts: '1/1_CONSUMED',
    predecessor_retry: false, predecessor_cleanup: false, predecessor_adoption: false,
    capsule: { executable_sha256: 'a'.repeat(64), images: [image] },
  };
  const manifestBytes = subject.canonicalJson(manifest);
  const receipt = {
    schema_version: 4, purpose: 'MAC_RELOCATABLE_NODE_CAPSULE_V4', authority,
    generation: 'capsule-v4', manifest_sha256: subject.sha256(manifestBytes),
    source_authority: 'e'.repeat(40),
    predecessor_authority: manifest.predecessor_authority, predecessor_generation: manifest.predecessor_generation,
    predecessor_status: manifest.predecessor_status, predecessor_attempts: manifest.predecessor_attempts,
    predecessor_retry: false, predecessor_cleanup: false, predecessor_adoption: false,
    capsule_executable_sha256: manifest.capsule.executable_sha256,
    capsule_images_sha256: subject.sha256(subject.canonicalJson(manifest.capsule.images)),
    move_probes: '2/2_PASS', loader_probes: '2/2_PASS', ready_handshakes: '2/2_PASS',
    stable_observations: '4/4_PASS', independent_source_observations: '2/2_PASS',
    mandatory_load_set_complete: true, weak_lazy_policy: 'PASS', copied_non_system_images_consumed: true,
    copied_but_unused: 0, attempts: 1, retry: false, raw_path: false,
  };
  const receiptBytes = subject.canonicalJson(receipt);
  const context = { authority: { commit: authority }, production_frozen_inputs: {
    ...productionFrozenInputBinding(), mac_node_capsule_receipt_sha256: subject.sha256(receiptBytes),
  } };
  const entry = (role, destination_relative_path, source_sha256, bytes) => ({
    role, destination_relative_path, source_sha256, bytes,
  });
  return { context, entries: [
    entry('node-runtime', 'runtime/node-capsule/capsule/bin/node', manifest.capsule.executable_sha256, Buffer.from('node')),
    entry('node-capsule-image-001', `runtime/node-capsule/capsule/${image.destination}`, image.sha256, Buffer.from('image')),
    entry('node-capsule-manifest', 'runtime/node-capsule/capsule-manifest.json', subject.sha256(manifestBytes), manifestBytes),
    entry('node-capsule-receipt', 'runtime/node-capsule/mac-relocatable-node-capsule.receipt.json', subject.sha256(receiptBytes), receiptBytes),
  ] };
}

test('[PRODUCTION-CONSUMER-1-V4] capsule source root uses the independent V4 namespace',()=>{
  const authority='a'.repeat(40),root=subject.macCapsuleSourceRoot({authority:{commit:authority}},'/Users/test');
  assert.equal(root,path.join('/Users/test','.config','agentempp','ci3','mac-node-capsule-v4',authority,'capsule-v4'));
});

test('[PRODUCTION-CONSUMER-2-CAPSULE-TOPOLOGY-RED/GREEN] Publisher1 installs the complete bound capsule closure', () => {
  const valid = capsuleInstallTopology();
  assert.equal(subject.validateMacCapsuleInstallTopology(valid.entries, valid.context), true);
  for (const mutate of [
    (value) => { value.entries.splice(1, 1); },
    (value) => { value.entries[0].destination_relative_path = 'runtime/node'; },
    (value) => { value.entries[1].source_sha256 = 'f'.repeat(64); },
    (value) => {
      const receipt = JSON.parse(value.entries.at(-1).bytes);
      receipt.predecessor_status = 'PASS';
      value.entries.at(-1).bytes = subject.canonicalJson(receipt);
      value.entries.at(-1).source_sha256 = subject.sha256(value.entries.at(-1).bytes);
      value.context.production_frozen_inputs.mac_node_capsule_receipt_sha256 = value.entries.at(-1).source_sha256;
    },
    (value) => {
      const manifest = JSON.parse(value.entries.at(-2).bytes);
      manifest.predecessor_authority = 'd'.repeat(40);
      value.entries.at(-2).bytes = subject.canonicalJson(manifest);
      value.entries.at(-2).source_sha256 = subject.sha256(value.entries.at(-2).bytes);
      const receipt = JSON.parse(value.entries.at(-1).bytes);
      receipt.predecessor_authority = manifest.predecessor_authority;
      receipt.manifest_sha256 = value.entries.at(-2).source_sha256;
      value.entries.at(-1).bytes = subject.canonicalJson(receipt);
      value.entries.at(-1).source_sha256 = subject.sha256(value.entries.at(-1).bytes);
      value.context.production_frozen_inputs.mac_node_capsule_receipt_sha256 = value.entries.at(-1).source_sha256;
    },
    (value) => {
      const manifest = JSON.parse(value.entries.at(-2).bytes);
      manifest.predecessor_generation = 'other-v3';
      value.entries.at(-2).bytes = subject.canonicalJson(manifest);
      value.entries.at(-2).source_sha256 = subject.sha256(value.entries.at(-2).bytes);
      const receipt = JSON.parse(value.entries.at(-1).bytes);
      receipt.predecessor_generation = manifest.predecessor_generation;
      receipt.manifest_sha256 = value.entries.at(-2).source_sha256;
      value.entries.at(-1).bytes = subject.canonicalJson(receipt);
      value.entries.at(-1).source_sha256 = subject.sha256(value.entries.at(-1).bytes);
      value.context.production_frozen_inputs.mac_node_capsule_receipt_sha256 = value.entries.at(-1).source_sha256;
    },
    (value) => { value.entries.at(-1).bytes = subject.canonicalJson({ purpose: 'MAC_RELOCATABLE_NODE_CAPSULE_V1' }); },
  ]) {
    const changed = capsuleInstallTopology(); mutate(changed);
    assert.throws(() => subject.validateMacCapsuleInstallTopology(changed.entries, changed.context),
      (error) => error?.code === 'STOP_PRE_AUTHORITY');
  }
});

function syntheticBindings() {
  return {
    MAC_EXECUTOR_AUTHORITY_SHA: '1'.repeat(40),
    MAC_EXECUTOR_AUTHORITY_PARENT: 'd4f7d37bbac98b5b0e37b459528a8d5c6adb3622',
    MAC_EXECUTOR_AUTHORITY_TREE: '3'.repeat(40),
    MAC_EXECUTOR_AUTHORITY_SUBJECT: controllerContract.AUTHORITY_SUBJECT,
    CURRENT_REMOTE_SHA: '4'.repeat(40),
    CURRENT_REMOTE_PARENT: '5'.repeat(40),
    CURRENT_REMOTE_TREE: '6'.repeat(40),
    CURRENT_REMOTE_SUBJECT: 'build(ops): synthetic remote fixture authority',
    MAC_OBJECT_BOOTSTRAP_AUTHORITY_SHA: '7'.repeat(40),
    REMOTE_BUNDLE_AUTHORITY_SHA: '8'.repeat(40),
    REMOTE_BUNDLE_AUTHORITY_PARENT: '9'.repeat(40),
    REMOTE_BUNDLE_AUTHORITY_TREE: 'a'.repeat(40),
    REMOTE_BUNDLE_AUTHORITY_SUBJECT: 'build(ops): synthetic immutable remote bundle authority',
    REMOTE_BUNDLE_DOCUMENTATION_SHA: 'b'.repeat(40),
    REMOTE_BUNDLE_GENERATION_ID: `rb-${'c'.repeat(64)}`,
    REMOTE_BUNDLE_RECEIPT_SHA256: 'd'.repeat(64),
    REMOTE_BUNDLE_CONFIG_SHA256: 'e'.repeat(64),
    REMOTE_SYNTHETIC_CREDENTIAL_SHA256: 'f'.repeat(64),
    NODE_RUNTIME_V2_CREATION_AUTHORITY_SHA: '1'.repeat(40),
    NODE_RUNTIME_V2_ADOPTION_AUTHORITY_SHA: '2'.repeat(40),
    CI3_IOS_AUTHORITY_SHA: '3'.repeat(40),
    CI2_BASE: '4'.repeat(40),
    AUTHORITY_BASE: '5'.repeat(40),
  };
}

function syntheticContext() {
  return {
    authority: {
      commit: H40,
      parent: 'e'.repeat(40),
      tree: 'f'.repeat(40),
      subject_sha256: '1'.repeat(64),
      manifest_sha256: '2'.repeat(64),
      components: {
        writer: { sha256: '3'.repeat(64) },
        controller: { sha256: '4'.repeat(64) },
        launcher: { sha256: '5'.repeat(64) },
      },
    },
    generations: {
      remote: REMOTE_GENERATION, controller: CONTROLLER_GENERATION,
      simulator: `simulator-${'a'.repeat(64)}`, terminal: `terminal-${'b'.repeat(64)}`,
    },
    collector_contracts_sha256: '6'.repeat(64),
    node_candidate_sha256: '7'.repeat(64),
    operation_authority_sha256: '8'.repeat(64),
  };
}

function syntheticObservation(role, root, index) {
  const sourcePath = path.join(root, `${role}.payload`);
  const metadata = {
    uid: 501,
    gid: 20,
    mode: 0o600,
    nlink: 1,
    size: index + 1,
    mtime_ns: `${1_700_000_000_000_000_000n + BigInt(index)}`,
    dev: `${100n + BigInt(index)}`,
    ino: `${1000n + BigInt(index)}`,
  };
  return {
    role,
    path: sourcePath,
    path_sha256: subject.sha256(Buffer.from(sourcePath)),
    sha256: String((index % 9) + 1).repeat(64),
    ...metadata,
    identity_sha256: subject.physicalIdentitySha256(metadata),
  };
}

function syntheticReceiver(root = '/private/var/folders/synthetic/receiver') {
  const observations = Object.fromEntries(subject.PUBLISHER1_ROLES.map((role, index) => [
    role,
    syntheticObservation(role, root, index),
  ]));
  const shaByRole = Object.fromEntries(Object.entries(observations).map(([role, value]) => [role, value.sha256]));
  return { root, observations, shaByRole };
}

function buildIssuerAndPass(context = syntheticContext()) {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const issuer = subject.buildVpsIssuerAuthority({
    authoritySha: context.authority.commit,
    issuerGenerationId: `issuer-${'9'.repeat(64)}`,
    publicKey,
  });
  const manifest = subject.buildPublisherInputManifest({
    context,
    entries: subject.TRANSPORT_ROLES.map((role, index) => ({
      role,
      path_sha256: String((index % 8) + 1).repeat(64),
      sha256: String(((index + 2) % 8) + 1).repeat(64),
    })),
  });
  const unsigned = subject.buildUnsignedVpsPass({
    context,
    issuer,
    publisherInputManifestSha256: subject.sha256(subject.canonicalJson(manifest)),
    transferPayloadSha256: manifest.transfer_payload_sha256,
  });
  const pass = subject.signVpsPass({ unsigned, issuer, privateKey });
  return { context, issuer, manifest, pass };
}

async function rejectCode(code, operation) {
  await assert.rejects(operation, (error) => error?.code === code);
}

async function writeOwnerOnlyFixture(file, bytes) {
  await mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  await writeFile(file, bytes, { flag: 'wx', mode: 0o600 });
  await chmod(file, 0o600);
}

function cliGate0(bindings, context) {
  return {
    schema_version: 2, purpose: 'CI3_SEMANTIC_SAFE_MAC_GATE0_V2',
    authority_sha: bindings.MAC_EXECUTOR_AUTHORITY_SHA,
    authority_manifest_sha256: context.authority.manifest_sha256,
    launcher_sha256: context.authority.components.launcher.sha256,
    exit_code: 0, stdout_bytes: 0, stderr_bytes: 0, status: 'PASS', raw_values: false,
  };
}

function buildSemanticPublisherOutputs(context, writerSourceBytes, {
  invalidLauncherAuthority = false, installerCompileAuthoritySha256, installerExpectedBinarySha256,
  installerSourceBytes = Buffer.from('synthetic installer source\n'), authorityInputsOnly = false,
  nodeBytes: suppliedNodeBytes = null, controllerBytes: suppliedControllerBytes = null,
  launcherBytes: suppliedLauncherBytes = null,
} = {}) {
  context.authority.components.writer.sha256 = subject.sha256(writerSourceBytes);
  const nodeBytes = suppliedNodeBytes ?? Buffer.from('successor-node-runtime\n');
  const controllerBytes = suppliedControllerBytes ?? Buffer.from('successor-controller\n');
  const launcherBytes = suppliedLauncherBytes ?? Buffer.from('successor-launcher\n');
  const transportedLauncherBytes = invalidLauncherAuthority
    ? Buffer.from('semantic-invalid-launcher-runtime\n')
    : launcherBytes;
  const authorityBytesByPath = new Map([
    ['scripts/ci3/ci3-bridge-controller.mjs', controllerBytes],
    ['scripts/ci3/ci3-bridge-launcher.zsh', launcherBytes],
    ['scripts/ci3/ci3-terminal-anchor-writer.swift', writerSourceBytes],
    ['scripts/ci3/ci3-publisher1-bootstrap-installer.swift', installerSourceBytes],
  ]);
  const authorityManifestBytes = Buffer.from(subject.PUBLISHER_AUTHORITY_PATHS.map((entryPath, index) => {
    const bytes = authorityBytesByPath.get(entryPath) ?? Buffer.from(`synthetic-authority-${index}\n`);
    return `${entryPath} ${subject.gitBlobOid(bytes)} ${subject.sha256(bytes)}`;
  }).join('\n') + '\n');
  context.node_candidate_sha256 = subject.sha256(nodeBytes);
  context.authority.subject = controllerContract.AUTHORITY_SUBJECT;
  context.authority.subject_sha256 = subject.sha256(Buffer.from(context.authority.subject));
  context.authority.components = {
    generator: { path: 'scripts/ci3/create-ios-staging-bridge-config.mjs', blob_oid: '1'.repeat(40), sha256: '1'.repeat(64) },
    controller: { path: 'scripts/ci3/ci3-bridge-controller.mjs', blob_oid: subject.gitBlobOid(controllerBytes), sha256: subject.sha256(controllerBytes) },
    launcher: { path: 'scripts/ci3/ci3-bridge-launcher.zsh', blob_oid: subject.gitBlobOid(launcherBytes), sha256: subject.sha256(launcherBytes) },
    writer: { path: 'scripts/ci3/ci3-terminal-anchor-writer.swift', blob_oid: subject.gitBlobOid(writerSourceBytes), sha256: subject.sha256(writerSourceBytes) },
  };
  context.authority.manifest_sha256 = subject.sha256(authorityManifestBytes);
  const sshBytes = {
    'ssh-config': Buffer.from('Host successor-only\n'),
    'ssh-known-hosts': Buffer.from('successor.invalid ssh-ed25519 synthetic\n'),
    'ssh-private-key': Buffer.from('synthetic-private-key-material\n'),
    'ssh-public-key': Buffer.from('ssh-ed25519 synthetic successor\n'),
    'ssh-trust-descriptor': subject.canonicalJson({ purpose: 'CI3_SEMANTIC_TRUST_V1', raw_values: false }),
  };
  const toolIdentities = {
    node: { path_sha256: '1'.repeat(64), binary_sha256: subject.sha256(nodeBytes), version_sha256: '2'.repeat(64) },
    ssh: { path_sha256: subject.sha256(Buffer.from('/usr/bin/ssh')), binary_sha256: '3'.repeat(64), version_sha256: '4'.repeat(64) },
    swiftc: { path_sha256: '5'.repeat(64), binary_sha256: '6'.repeat(64), version_sha256: '7'.repeat(64) },
    xcodebuild: { path_sha256: '8'.repeat(64), binary_sha256: '9'.repeat(64), version_sha256: 'a'.repeat(64) },
  };
  const scans = Object.fromEntries(controllerContract.TERMINAL_SCAN_IDS.map((id) => [id, {
    id, collector_version: controllerContract.SCAN_SURFACE_CONTRACTS[id].collector_version,
    format: controllerContract.SCAN_SURFACE_CONTRACTS[id].format,
    source_role: controllerContract.SCAN_SURFACE_CONTRACTS[id].source_role,
    contract_sha256: controllerContract.scannerSchemaSha256(id), tool_sha256: subject.sha256(controllerBytes),
  }]));
  context.collector_contracts_sha256 = subject.sha256(subject.canonicalJson(scans));
  const remoteRecord = {
    receipt_path: '/synthetic/successor/bridge.receipt.json',
    config_path: '/synthetic/successor/bundle/mobile-staging-config.json',
    credential_path: '/synthetic/successor/bundle/synthetic-credential.json',
  };
  const operationAuthorityBytes = subject.canonicalJson({
    schema_version: 1, purpose: 'CI3_MAC_OPERATION_AUTHORITY_V1',
    context: {
      authority: {
        commit: context.authority.commit, parent: context.authority.parent, tree: context.authority.tree,
        subject: context.authority.subject, manifest_sha256: context.authority.manifest_sha256,
        components: context.authority.components,
      },
      generations: { ...context.generations },
      remote: {
        bundle_path_sha256: subject.sha256(Buffer.from(path.dirname(remoteRecord.config_path))),
        receipt_path_sha256: subject.sha256(Buffer.from(remoteRecord.receipt_path)), receipt_sha256: '1'.repeat(64),
        config_path_sha256: subject.sha256(Buffer.from(remoteRecord.config_path)), config_sha256: '2'.repeat(64),
        credential_path_sha256: subject.sha256(Buffer.from(remoteRecord.credential_path)), credential_sha256: '3'.repeat(64),
      },
    },
    worktree: {
      branch: 'codex/ci3-today-staging-v1', changed_paths: [...controllerContract.PRESERVED_CI3_PATHS],
      continuation_allowlist_sha256: controllerContract.CONTINUATION_ALLOWLIST_SHA256,
      diff_sha256: '4'.repeat(64), head: '277873755bf29771a10b5f362b522c2e6a6c21d6', status_sha256: '5'.repeat(64),
    },
    simulator: {
      app_installation_sha256: '1'.repeat(64), container_identity_sha256: '2'.repeat(64),
      container_path_sha256: '3'.repeat(64), device_selection_sha256: '4'.repeat(64), device_udid: 'synthetic-device',
      probe_ack_sha256: '5'.repeat(64), probe_config_path: '/synthetic/probe-config', probe_config_sha256: '6'.repeat(64),
      probe_credential_path: '/synthetic/probe-credential', probe_credential_sha256: '7'.repeat(64), runtime_sha256: '8'.repeat(64),
    },
    ssh: {
      alias: 'ci3-successor', code_signature_sha256: '1'.repeat(64), config_path: '/synthetic/ssh/config',
      config_sha256: subject.sha256(sshBytes['ssh-config']), destination_sha256: '2'.repeat(64),
      effective_config_sha256: '3'.repeat(64), executable_path_sha256: subject.sha256(Buffer.from('/usr/bin/ssh')),
      executable_sha256: toolIdentities.ssh.binary_sha256, host_key_ed25519_sha256: '4'.repeat(64),
      identity_path: '/synthetic/ssh/id', identity_public_key_fingerprint_sha256: '5'.repeat(64),
      identity_public_key_path: '/synthetic/ssh/id.pub', identity_public_key_sha256: subject.sha256(sshBytes['ssh-public-key']),
      identity_sha256: subject.sha256(sshBytes['ssh-private-key']), known_hosts_path: '/synthetic/ssh/known-hosts',
      known_hosts_sha256: subject.sha256(sshBytes['ssh-known-hosts']), port: 22,
      trust_descriptor_path: '/synthetic/ssh/trust.json', trust_descriptor_sha256: subject.sha256(sshBytes['ssh-trust-descriptor']),
      version_sha256: toolIdentities.ssh.version_sha256,
    },
    remote: remoteRecord, scans,
    writer: {
      authority_path: '/synthetic/writer-authority', manifest_path: '/synthetic/writer-manifest',
      phase_target_contracts: controllerContract.CONTROLLER_EVIDENCE_PHASES.map((phase, index) => ({
        phase, targets: [{ role: `synthetic-${index}`, state: 'PRESENT', path_sha256: String((index % 8) + 1).repeat(64),
          modes: [0o444], allowed_uids: [0], allowed_gids: [0], immutable: true }],
      })),
    }, raw_values: false,
  });
  context.operation_authority_sha256 = subject.sha256(operationAuthorityBytes);
  const launchAttestationBytes = subject.canonicalJson({
    schema_version: 1, purpose: 'CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2', authority_sha: context.authority.commit,
    authority_parent: context.authority.parent, authority_tree: context.authority.tree,
    authority_subject_sha256: context.authority.subject_sha256,
    authority_manifest_sha256: context.authority.manifest_sha256,
    components: context.authority.components, tools: toolIdentities, raw_values: false,
  });
  const transportBytes = {
    'node-runtime': nodeBytes,
    controller: controllerBytes,
    'launcher-runtime': transportedLauncherBytes,
    'launch-attestation': launchAttestationBytes,
    'authority-manifest': authorityManifestBytes,
    'operation-authority': operationAuthorityBytes,
    ...sshBytes,
  };
  if (authorityInputsOnly) {
    return { transportBytes, authorityManifestBytes };
  }
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const issuer = subject.buildVpsIssuerAuthority({
    authoritySha: context.authority.commit, issuerGenerationId: `issuer-${'9'.repeat(64)}`, publicKey,
  });
  const manifest = subject.buildPublisherInputManifest({
    context,
    entries: subject.TRANSPORT_ROLES.map((role, index) => ({
      role, path_sha256: String((index % 8) + 1).repeat(64), sha256: subject.sha256(transportBytes[role]),
    })),
  });
  const pass = subject.signVpsPass({
    unsigned: subject.buildUnsignedVpsPass({
      context, issuer, publisherInputManifestSha256: subject.sha256(subject.canonicalJson(manifest)),
      transferPayloadSha256: manifest.transfer_payload_sha256,
    }),
    issuer, privateKey,
  });
  const human = {
    schema_version: 1, purpose: 'CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V1',
    authority_sha: context.authority.commit, approved_action: 'PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY',
    authority_manifest_sha256: context.authority.manifest_sha256,
    operation_authority_sha256: context.operation_authority_sha256,
    publisher_input_manifest_sha256: subject.sha256(subject.canonicalJson(manifest)),
    vps_operation_authority_pass_sha256: subject.sha256(subject.canonicalJson(pass)),
    node_binary_sha256: context.node_candidate_sha256, attempt: 1, retry: false, raw_values: false,
  };
  if (installerCompileAuthoritySha256 !== undefined || installerExpectedBinarySha256 !== undefined) {
    assert.match(installerCompileAuthoritySha256, /^[a-f0-9]{64}$/);
    assert.match(installerExpectedBinarySha256, /^[a-f0-9]{64}$/);
    human.publisher_installer_compile_authority_sha256 = installerCompileAuthoritySha256;
    human.publisher_installer_expected_binary_sha256 = installerExpectedBinarySha256;
  }
  const launcherAuthorityBytes = Buffer.from([
      'CI3_EXTERNAL_LAUNCHER_AUTHORITY_V1', `authority_sha ${context.authority.commit}`,
      `controller_generation_id ${context.generations.controller}`, `node_sha256 ${subject.sha256(nodeBytes)}`,
      `controller_sha256 ${subject.sha256(controllerBytes)}`, `launcher_sha256 ${subject.sha256(transportedLauncherBytes)}`,
      `launch_attestation_sha256 ${subject.sha256(launchAttestationBytes)}`,
      `authority_manifest_sha256 ${subject.sha256(authorityManifestBytes)}`,
      'allowed_modes --self-test,plan,verify-simulator,verify-ssh,fetch,install-simulator,scan,write-terminal-anchor,resume,publish-operation-authority,publish-privileged-writer-authority,status',
      'raw_values false', '',
    ].join('\n'));
  const bytesByRole = {
    ...transportBytes,
    'launcher-bootstrap-authority': launcherAuthorityBytes,
    'human-authorization': subject.canonicalJson(human),
    'vps-pass': subject.canonicalJson(pass),
    'vps-issuer-authority': subject.canonicalJson(issuer),
    'publisher-input-manifest': subject.canonicalJson(manifest),
  };
  assert.deepEqual(Object.keys(bytesByRole).sort(), [...subject.PUBLISHER1_ROLES].sort());
  return {
    issuerBytes: subject.canonicalJson(issuer), passBytes: subject.canonicalJson(pass),
    manifestBytes: subject.canonicalJson(manifest), bytesByRole,
    receiverManifestSha256: subject.sha256(subject.canonicalJson(manifest)), authorityManifestBytes,
  };
}

function fixedOutputProducerScript(entries, markerPath) {
  const encoded = Buffer.from(JSON.stringify(entries.map(([file, bytes]) => [file, bytes.toString('base64')]))).toString('base64');
  return `#!/usr/bin/python3\nimport base64,json,os\nitems=json.loads(base64.b64decode(${JSON.stringify(encoded)}))\nfor file_name,encoded_bytes in items:\n parent=os.path.dirname(file_name)\n os.makedirs(parent,mode=0o700,exist_ok=True)\n os.chmod(parent,0o700)\n descriptor=os.open(file_name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)\n try:\n  os.write(descriptor,base64.b64decode(encoded_bytes))\n  os.fchmod(descriptor,0o600)\n  os.fsync(descriptor)\n finally:\n  os.close(descriptor)\nmarker=${JSON.stringify(markerPath)}\nparent=os.path.dirname(marker)\nos.makedirs(parent,mode=0o700,exist_ok=True)\ndescriptor=os.open(marker,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)\nos.close(descriptor)\n`;
}

function fixedStdoutProducerScript(bytes, markerPath) {
  const encoded = bytes.toString('base64');
  return `#!/usr/bin/python3\nimport base64,os,sys\nsys.stdout.buffer.write(base64.b64decode(${JSON.stringify(encoded)}))\nsys.stdout.buffer.flush()\nmarker=${JSON.stringify(markerPath)}\nparent=os.path.dirname(marker)\nos.makedirs(parent,mode=0o700,exist_ok=True)\ndescriptor=os.open(marker,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)\nos.close(descriptor)\n`;
}

function fixedFakeSshTransportScript(markerPath) {
  return `#!/bin/sh
set -eu
test "$#" -eq 8
test "$1" = -F
test "$3" = -o
test "$4" = BatchMode=yes
test "$5" = -o
test "$6" = NumberOfPasswordPrompts=0
test "$7" = ci3-publisher0
( set -C; : > ${JSON.stringify(markerPath)} )
/bin/chmod 600 ${JSON.stringify(markerPath)}
exec /bin/sh -c "$8"
`;
}

function expectedZeroPreseedPublisherManifest(context, bootstrapInputs) {
  const relativePath = (role) => {
    if (role === 'node-runtime') return `runtime/node-${context.node_candidate_sha256}`;
    if (role === 'controller') return `git/${context.authority.components.controller.blob_oid}/ci3-bridge-controller.mjs`;
    if (role === 'launcher-runtime') return `git/${context.authority.components.launcher.blob_oid}/ci3-bridge-launcher.zsh`;
    return `inputs/${role}.payload`;
  };
  const mode = (role) => role === 'node-runtime' || role === 'controller' || role === 'launcher-runtime'
    ? 0o555 : role === 'ssh-private-key' ? 0o400 : 0o444;
  const provenanceEntries = subject.TRANSPORT_ROLES.map((role) => ({
    role, relative_path: relativePath(role), sha256: subject.sha256(bootstrapInputs[role]),
    byte_length: bootstrapInputs[role].length, mode: mode(role),
    git_path: role === 'controller' || role === 'launcher-runtime'
      ? context.authority.components[role === 'controller' ? 'controller' : 'launcher'].path : null,
    git_blob_oid: role === 'controller' || role === 'launcher-runtime'
      ? context.authority.components[role === 'controller' ? 'controller' : 'launcher'].blob_oid : null,
  }));
  const inputProvenance = {
    authority_sha: context.authority.commit, authority_manifest_sha256: context.authority.manifest_sha256,
    entries: provenanceEntries,
  };
  const transactionGenerationId = `publisher0-${subject.sha256(subject.canonicalJson(inputProvenance))}`;
  const fixedTransactionRoot = `/var/lib/agentempp/ci3-vps-authority/${context.authority.commit}/${transactionGenerationId}`;
  const entries = subject.TRANSPORT_ROLES.map((role) => ({
    role, path_sha256: subject.sha256(Buffer.from(`${fixedTransactionRoot}/publisher-input/${role}.payload`)),
    sha256: subject.sha256(bootstrapInputs[role]),
  }));
  const manifest = {
    schema_version: 1, purpose: 'CI3_VPS_PUBLISHER_INPUT_MANIFEST_V2', authority_sha: context.authority.commit,
    remote_generation_id: context.generations.remote, controller_generation_id: context.generations.controller,
    collector_contracts_sha256: context.collector_contracts_sha256, entries,
    transfer_payload_sha256: subject.sha256(subject.canonicalJson(entries)), raw_values: false,
  };
  return { manifest, transactionGenerationId };
}

async function createActualCliFixture(label, { frozenWriter = false, semanticInvalidLauncherAuthority = false } = {}) {
  const root = await realpath(await mkdtemp(path.join(tmpdir(), `ci3-external-cli-${label}-`)));
  const bindings = syntheticBindings();
  const context = syntheticContext();
  context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
  context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
  context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
  context.authority.subject_sha256 = subject.sha256(Buffer.from(bindings.MAC_EXECUTOR_AUTHORITY_SUBJECT));
  const writerSourceBytes = await readFile(WRITER_SOURCE);
  let writerBytes = Buffer.from('#!/bin/sh\nexit 0\n');
  if (frozenWriter) {
    const writerBuildPath = path.join(root, 'ci3-terminal-anchor-writer.synthetic');
    const compiled = spawnSync('/usr/bin/xcrun', ['swiftc', '-parse-as-library', '-D', 'CI3_SYNTHETIC_TEST',
      path.join(path.dirname(CHAIN_SCRIPT), 'ci3-terminal-anchor-writer.swift'), '-o', writerBuildPath], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 120_000, maxBuffer: 1024 * 1024,
    });
    assert.equal(compiled.status, 0, `${compiled.stdout}\n${compiled.stderr}`);
    writerBytes = await readFile(writerBuildPath);
  }
  const authorityRoot = path.join(root, 'owner', bindings.MAC_EXECUTOR_AUTHORITY_SHA);
  const sourceRoot = path.join(authorityRoot, 'frozen');
  const producedRuntimeRoot = path.join(sourceRoot, 'publisher1-produced', 'runtime');
  await mkdir(producedRuntimeRoot, { recursive: true, mode: 0o700 });
  await chmod(producedRuntimeRoot, 0o700);
  const installerCandidatePath = path.join(sourceRoot, 'publisher1-input', 'installer.swift');
  const installerBytes = await readFile(INSTALLER_SOURCE);
  await writeOwnerOnlyFixture(installerCandidatePath, installerBytes);
  const compilerSelection = spawnSync('/usr/bin/xcrun', ['--find', 'swiftc'], {
    encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 30_000, maxBuffer: 16 * 1024,
  });
  assert.equal(compilerSelection.status, 0, compilerSelection.stderr);
  assert.match(compilerSelection.stdout, /^\/[^\0\r\n]+\n$/);
  const compilerPath = compilerSelection.stdout.slice(0, -1);
  const resolvedCompilerPath = await realpath(compilerPath);
  const compilerBytes = await readFile(resolvedCompilerPath);
  const compilerStat = await lstat(resolvedCompilerPath, { bigint: true });
  const compilerMetadata = {
    uid: Number(compilerStat.uid), gid: Number(compilerStat.gid), mode: Number(compilerStat.mode & 0o777n),
    nlink: Number(compilerStat.nlink), size: Number(compilerStat.size), mtime_ns: String(compilerStat.mtimeNs),
    dev: String(compilerStat.dev), ino: String(compilerStat.ino),
  };
  assert.equal(compilerMetadata.uid, 0);
  assert.equal(compilerMetadata.gid, 0);
  assert.equal(compilerMetadata.mode, 0o755);
  assert.equal(compilerMetadata.nlink, 1);
  const installerBinaryPath = path.join(producedRuntimeRoot, 'ci3-publisher1-bootstrap-installer');
  const installerCompileArguments = ['swiftc', '-D', 'CI3_SYNTHETIC_TEST', installerCandidatePath, '-o', installerBinaryPath];
  const expectedCompilation = spawnSync('/usr/bin/xcrun', installerCompileArguments, {
    encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 120_000, maxBuffer: 1024 * 1024,
  });
  assert.equal(expectedCompilation.status, 0, `${expectedCompilation.stdout}\n${expectedCompilation.stderr}`);
  const installerExpectedBinarySha256 = subject.sha256(await readFile(installerBinaryPath));
  await rm(installerBinaryPath);
  const compilerPathSha256 = subject.sha256(Buffer.from(compilerPath));
  const compilerSha256 = subject.sha256(compilerBytes);
  const compilerIdentitySha256 = subject.physicalIdentitySha256(compilerMetadata);
  const resolvedDriverPath = await realpath('/usr/bin/xcrun');
  const driverBytes = await readFile(resolvedDriverPath);
  const driverStat = await lstat(resolvedDriverPath, { bigint: true });
  const driverMetadata = {
    uid: Number(driverStat.uid), gid: Number(driverStat.gid), mode: Number(driverStat.mode & 0o777n),
    nlink: Number(driverStat.nlink), size: Number(driverStat.size), mtime_ns: String(driverStat.mtimeNs),
    dev: String(driverStat.dev), ino: String(driverStat.ino),
  };
  const driverPathSha256 = subject.sha256(Buffer.from('/usr/bin/xcrun'));
  const driverSha256 = subject.sha256(driverBytes);
  const driverIdentitySha256 = subject.physicalIdentitySha256(driverMetadata);
  const compileArgvSha256 = subject.sha256(subject.canonicalJson(installerCompileArguments));
  const toolchainProvenanceSha256 = subject.sha256(subject.canonicalJson({
    driver_path_sha256: driverPathSha256, driver_sha256: driverSha256,
    driver_identity_sha256: driverIdentitySha256,
    compiler_path_sha256: compilerPathSha256, compiler_sha256: compilerSha256,
    compiler_identity_sha256: compilerIdentitySha256, compile_argv_sha256: compileArgvSha256,
  }));
  const controllerBytes = await readFile(CHAIN_SCRIPT.replace('ci3-external-publisher-chain.mjs', 'ci3-bridge-controller.mjs'));
  const launcherBytes = await readFile(CHAIN_SCRIPT.replace('ci3-external-publisher-chain.mjs', 'ci3-bridge-launcher.zsh'));
  const nodeBytes = Buffer.from(`#!/bin/sh\nexec ${JSON.stringify(process.execPath)} "$@"\n`);
  const authorityInputs = buildSemanticPublisherOutputs(context, writerSourceBytes, {
    invalidLauncherAuthority: semanticInvalidLauncherAuthority,
    installerSourceBytes: installerBytes,
    authorityInputsOnly: true, nodeBytes, controllerBytes, launcherBytes,
  });
  const publisherOutputs = {
    authorityManifestBytes: authorityInputs.authorityManifestBytes,
    bytesByRole: authorityInputs.transportBytes,
  };
  const expectedPublisher0 = expectedZeroPreseedPublisherManifest(context, authorityInputs.transportBytes);
  const installerCompileAuthorityBytes = subject.canonicalJson({
    schema_version: 3, purpose: 'CI3_PUBLISHER1_INSTALLER_COMPILE_AUTHORITY_V3', authority_sha: context.authority.commit,
    controller_generation_id: context.generations.controller,
    authority_manifest_sha256: subject.sha256(publisherOutputs.authorityManifestBytes),
    source_git_path: 'scripts/ci3/ci3-publisher1-bootstrap-installer.swift',
    source_git_blob_oid: subject.gitBlobOid(installerBytes),
    source_path_sha256: subject.sha256(Buffer.from(installerCandidatePath)), source_sha256: subject.sha256(installerBytes),
    compiler_path_sha256: compilerPathSha256, compiler_sha256: compilerSha256,
    compiler_identity_sha256: compilerIdentitySha256, compile_argv_sha256: compileArgvSha256,
    driver_path_sha256: driverPathSha256, driver_sha256: driverSha256,
    driver_identity_sha256: driverIdentitySha256,
    toolchain_provenance_sha256: toolchainProvenanceSha256,
    expected_binary_sha256: installerExpectedBinarySha256,
    binary_relative_path: 'runtime/ci3-publisher1-bootstrap-installer', attempt: 1, retry: false, raw_values: false,
  });
  await writeOwnerOnlyFixture(path.join(sourceRoot, 'publisher1-input', 'installer.authority.json'), installerCompileAuthorityBytes);
  await writeOwnerOnlyFixture(path.join(root, 'authorities.json'), subject.canonicalJson(bindings));
  await writeOwnerOnlyFixture(path.join(sourceRoot, 'context.json'), subject.canonicalJson(context));
  await writeOwnerOnlyFixture(path.join(sourceRoot, 'gate0.json'), subject.canonicalJson(cliGate0(bindings, context)));
  await writeOwnerOnlyFixture(path.join(sourceRoot, 'prompt.sha256'), Buffer.from(`${'f'.repeat(64)}\n`));
  for (const [index, role] of subject.PREPARE_CANDIDATE_ROLES.entries()) {
    await writeOwnerOnlyFixture(path.join(sourceRoot, 'candidates', `${role}.payload`), Buffer.from(`candidate-${index}\n`));
  }
  for (const role of subject.TRANSPORT_ROLES) {
    await writeOwnerOnlyFixture(
      path.join(sourceRoot, 'publisher0-authority-input', `${role}.payload`), authorityInputs.transportBytes[role],
    );
  }
  await writeOwnerOnlyFixture(path.join(sourceRoot, 'publisher1-input', 'writer.bin'), writerBytes);
  await chmod(path.join(sourceRoot, 'publisher1-input', 'writer.bin'), 0o500);
  await writeOwnerOnlyFixture(path.join(sourceRoot, 'publisher1-input', 'writer.swift'), writerSourceBytes);
  await writeOwnerOnlyFixture(path.join(sourceRoot, 'frozen-authority-projection.json'), subject.canonicalJson({
    authority_sha: context.authority.commit, authority_parent: context.authority.parent, authority_tree: context.authority.tree,
    authority_subject_sha256: context.authority.subject_sha256, authority_manifest_sha256: context.authority.manifest_sha256,
    operation_authority_sha256: context.operation_authority_sha256, node_candidate_sha256: context.node_candidate_sha256,
    collector_contracts_sha256: context.collector_contracts_sha256, remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
  }));
  await mkdir(path.join(root, 'publisher1-terminal-authority'), { recursive: true, mode: 0o700 });
  await chmod(path.join(root, 'publisher1-terminal-authority'), 0o700);
  await mkdir(path.join(root, 'publisher1-terminal-state', context.authority.commit, context.generations.controller), {
    recursive: true, mode: 0o700,
  });
  await chmod(path.join(root, 'publisher1-terminal-state', context.authority.commit, context.generations.controller), 0o700);
  const operations = ['provision-vps-publisher0', 'receive-vps-pass', 'provision-mac-publisher1', 'verify-chain'];
  for (const operation of operations) {
    const mode = `--${operation}`;
    await mkdir(path.join(authorityRoot, 'state', operation), { recursive: true, mode: 0o700 });
    const adapter = path.join(root, 'fixed-bin', operation);
    await mkdir(path.dirname(adapter), { recursive: true, mode: 0o700 });
    const outputEntries = [];
    const markerPath = path.join(root, 'fixed-bin', `${operation}.ran`);
    const adapterBytes = Buffer.from(operation === 'provision-vps-publisher0'
      ? fixedFakeSshTransportScript(markerPath)
      : fixedOutputProducerScript(outputEntries, markerPath));
    await writeFile(adapter, adapterBytes, { mode: 0o700 });
    await chmod(adapter, 0o700);
    const modeAuthority = operation === 'provision-vps-publisher0'
      ? {
        schema_version: 2, purpose: 'CI3_EXTERNAL_PUBLISHER_PROVISION_VPS_PUBLISHER0_AUTHORITY_V2',
        authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
        fixed_executable_sha256: subject.sha256(adapterBytes), attempt: 1, retry: false, raw_values: false,
      }
      : {
        schema_version: 1, purpose: `CI3_EXTERNAL_PUBLISHER_${operation.replaceAll('-', '_').toUpperCase()}_AUTHORITY_V1`,
        authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
        attempt: 1, retry: false, raw_values: false,
      };
    await writeOwnerOnlyFixture(
      path.join(sourceRoot, 'operations', `${operation}.authority.json`), subject.canonicalJson(modeAuthority),
    );
    assert.equal(mode.startsWith('--'), true);
  }
  return {
    root, sourceRoot, authorityRoot, context, publisherOutputs,
    fakeRemoteRoot: path.join(root, 'publisher0-fake-remote'),
    receiverManifestSha256: subject.sha256(subject.canonicalJson(expectedPublisher0.manifest)),
    publisher0TransactionGenerationId: expectedPublisher0.transactionGenerationId,
  };
}

function runActualCli(root, mode, extraEnvironment = {}) {
  return spawnSync(process.execPath, [CHAIN_SCRIPT, mode], {
    encoding: 'utf8', timeout: 30_000, maxBuffer: 64 * 1024,
    env: { HOME: root, LANG: 'C', LC_ALL: 'C', PATH: process.env.PATH ?? '/usr/bin:/bin',
      CI3_SYNTHETIC_TEST: '1', CI3_SYNTHETIC_TEST_ROOT: root, ...extraEnvironment },
  });
}

function spawnActualCli(root, mode, extraEnvironment = {}) {
  return spawn(process.execPath, [CHAIN_SCRIPT, mode], {
    env: { HOME: root, LANG: 'C', LC_ALL: 'C', PATH: process.env.PATH ?? '/usr/bin:/bin',
      CI3_SYNTHETIC_TEST: '1', CI3_SYNTHETIC_TEST_ROOT: root, ...extraEnvironment },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

async function waitForFixturePath(filePath, child, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const observed = await lstat(filePath).catch((error) => {
      if (error?.code === 'ENOENT') return null;
      throw error;
    });
    if (observed !== null) return observed;
    if (child.exitCode !== null || child.signalCode !== null) throw new Error('child exited before fixture path');
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('timed out waiting for fixture path');
}

async function waitForPublisher0BrokerPid(outer, timeoutMs = 3_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const observed = spawnSync('/bin/ps', ['-axo', 'pid=,ppid=,command='], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C' },
    });
    assert.equal(observed.status, 0);
    for (const line of observed.stdout.split('\n')) {
      const match = /^\s*(\d+)\s+(\d+)\s+(.+)$/u.exec(line);
      if (match === null) continue;
      const pid = Number(match[1]);
      const parentPid = Number(match[2]);
      if (parentPid === outer.pid && match[3].includes('--internal-publisher0-transport-broker')) return pid;
    }
    if (outer.exitCode !== null || outer.signalCode !== null) throw new Error('outer exited before broker identity');
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('timed out waiting for broker identity');
}

async function waitForFixtureProcessPid(fixtureRoot, mode, child, timeoutMs = 5_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const observed = spawnSync('/bin/ps', ['-axo', 'pid=,command='], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C' },
    });
    assert.equal(observed.status, 0);
    for (const line of observed.stdout.split('\n')) {
      const match = /^\s*(\d+)\s+(.+)$/u.exec(line);
      if (match !== null && match[2].includes(fixtureRoot) && match[2].split(/\s+/u).includes(mode)) return Number(match[1]);
    }
    if (child.exitCode !== null || child.signalCode !== null) throw new Error(`child exited before ${mode}`);
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`timed out waiting for ${mode}`);
}

async function waitForReplacementFixtureProcessPid(
  fixtureRoot, mode, previousPid, child, timeoutMs = 5_000,
) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const observed = spawnSync('/bin/ps', ['-axo', 'pid=,command='], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C' },
    });
    assert.equal(observed.status, 0);
    for (const line of observed.stdout.split('\n')) {
      const match = /^\s*(\d+)\s+(.+)$/u.exec(line);
      if (match !== null && Number(match[1]) !== previousPid
          && match[2].includes(fixtureRoot) && match[2].split(/\s+/u).includes(mode)) {
        return Number(match[1]);
      }
    }
    if (child.exitCode !== null || child.signalCode !== null) {
      throw new Error(`child exited before replacement ${mode}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`timed out waiting for replacement ${mode}`);
}

function fixtureHasProcessMode(fixtureRoot, mode) {
  const observed = spawnSync('/bin/ps', ['-axo', 'command='], {
    encoding: 'utf8', env: { PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C' },
  });
  assert.equal(observed.status, 0);
  return observed.stdout.split('\n').some((command) => (
    command.includes(fixtureRoot) && command.split(/\s+/u).includes(mode)
  ));
}

async function collectActualCli(child, timeoutMs = 30_000) {
  const stdout = [];
  const stderr = [];
  child.stdout.on('data', (chunk) => stdout.push(Buffer.from(chunk)));
  child.stderr.on('data', (chunk) => stderr.push(Buffer.from(chunk)));
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('child timeout')), timeoutMs);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
    child.once('close', (status, signal) => { clearTimeout(timer); resolve({ status, signal }); });
  });
  return { ...result, stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8') };
}

async function cleanupSyntheticFixture(root) {
  let entries = [];
  try { entries = await readdir(root, { withFileTypes: true }); } catch { return; }
  spawnSync('/usr/bin/chflags', ['-R', 'nouchg', root], { stdio: 'ignore' });
  await chmod(root, 0o700);
  for (const entry of entries) {
    if (entry.isDirectory() && !entry.isSymbolicLink()) await cleanupSyntheticFixture(path.join(root, entry.name));
  }
  await rm(root, { recursive: true, force: true });
}

async function createPublisher0PhysicalRaceFixture(label) {
  const fakeRemoteParent = await realpath(await mkdtemp(path.join(tmpdir(), `ci3-p0-physical-${label}-`)));
  const fakeRemoteRoot = path.join(fakeRemoteParent, 'root');
  const context = syntheticContext();
  const bindings = syntheticBindings();
  context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
  context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
  context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
  context.authority.subject_sha256 = subject.sha256(Buffer.from(controllerContract.AUTHORITY_SUBJECT));
  const writerSourceBytes = await readFile(WRITER_SOURCE);
  const controllerBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-controller.mjs', import.meta.url)));
  const launcherBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-launcher.zsh', import.meta.url)));
  const nodeBytes = Buffer.from(`#!/bin/sh\nexec ${JSON.stringify(process.execPath)} "$@"\n`);
  const { transportBytes: bootstrapInputs } = buildSemanticPublisherOutputs(context, writerSourceBytes, {
    authorityInputsOnly: true, nodeBytes, controllerBytes, launcherBytes,
  });
  const invocation = subject.buildPublisher0GitBoundBootstrapInvocation({
    configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', context,
    bootstrapInputs, syntheticRemoteRoot: fakeRemoteRoot,
    syntheticBarrierStage: 'physical-freeze-readback',
    durableTransport: false,
  });
  const remote = spawn('/bin/sh', ['-c', invocation.argv[7]], {
    env: { PATH: '/usr/bin:/bin' }, stdio: ['pipe', 'pipe', 'pipe'],
  });
  const completion = collectActualCli(remote);
  remote.stdin.end(invocation.input);
  const barrierRoot = path.join(fakeRemoteRoot, '.ci3-synthetic-barriers');
  const preparedPath = path.join(barrierRoot, 'publisher0-physical-freeze-readback.prepared.json');
  await waitForFixturePath(preparedPath, remote);
  const preparedBytes = await readFile(preparedPath);
  const prepared = JSON.parse(preparedBytes.toString('utf8'));
  assert.deepEqual(subject.canonicalJson(prepared), preparedBytes);
  assert.deepEqual(prepared, {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER0_PHYSICAL_BARRIER_V1',
    stage: 'physical-freeze-readback',
    request_sha256: invocation.request_sha256,
    decision: 'PREPARED',
    raw_values: false,
  });
  const release = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER0_PHYSICAL_BARRIER_RELEASE_V1',
    stage: prepared.stage,
    request_sha256: prepared.request_sha256,
    prepared_sha256: subject.sha256(preparedBytes),
    decision: 'CONTINUE',
    raw_values: false,
  };
  const releasePath = path.join(barrierRoot, 'publisher0-physical-freeze-readback.continue.json');
  const objectRoot = path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-authority-objects', context.authority.commit);
  const controllerPath = path.join(objectRoot, 'git', context.authority.components.controller.blob_oid, 'ci3-bridge-controller.mjs');
  const transactionBase = path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority', context.authority.commit);
  const { transactionGenerationId } = expectedZeroPreseedPublisherManifest(context, bootstrapInputs);
  return {
    fakeRemoteParent, fakeRemoteRoot, objectRoot, controllerPath, transactionBase,
    transactionRoot: path.join(transactionBase, transactionGenerationId),
    controllerBytes, releasePath, releaseBytes: subject.canonicalJson(release), remote, completion,
  };
}

async function snapshotFixtureTree(root) {
  const observations = [];
  const visit = async (current, relativePath) => {
    const observed = await lstat(current, { bigint: true });
    const record = {
      relative_path: relativePath, mode: Number(observed.mode & 0o777n), uid: observed.uid.toString(),
      gid: observed.gid.toString(), nlink: observed.nlink.toString(), dev: observed.dev.toString(),
      ino: observed.ino.toString(), size: observed.size.toString(), mtime_ns: observed.mtimeNs.toString(),
    };
    if (observed.isDirectory() && !observed.isSymbolicLink()) {
      record.kind = 'directory';
      observations.push(record);
      for (const name of (await readdir(current)).sort()) {
        await visit(path.join(current, name), relativePath === '.' ? name : `${relativePath}/${name}`);
      }
    } else {
      record.kind = observed.isFile() ? 'file' : 'other';
      if (record.kind === 'file') record.sha256 = subject.sha256(await readFile(current));
      observations.push(record);
    }
  };
  await visit(root, '.');
  return observations;
}

async function releasePublisher1PhaseB(continuationRoot) {
  const preparedPath = path.join(continuationRoot, 'publisher1-phase-b.prepared.json');
  const preparedBytes = await readFile(preparedPath);
  const prepared = JSON.parse(preparedBytes.toString('utf8'));
  assert.deepEqual(subject.canonicalJson(prepared), preparedBytes);
  assert.equal(prepared.purpose, 'CI3_SYNTHETIC_PUBLISHER1_PHASE_B_BARRIER_V1');
  assert.equal(prepared.stage, 'IMMEDIATELY_BEFORE_PHASE_B_OBSERVE_WRITE');
  assert.equal(prepared.decision, 'PREPARED');
  assert.equal(prepared.raw_values, false);
  const release = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER1_PHASE_B_BARRIER_RELEASE_V1',
    authority_sha: prepared.authority_sha,
    controller_generation_id: prepared.controller_generation_id,
    immutable_request_sha256: prepared.immutable_request_sha256,
    installed_self_sha256: prepared.installed_self_sha256,
    prepared_sha256: subject.sha256(preparedBytes),
    stage: prepared.stage,
    decision: 'CONTINUE',
    raw_values: false,
  };
  await writeOwnerOnlyFixture(
    path.join(continuationRoot, 'publisher1-phase-b.continue.json'), subject.canonicalJson(release),
  );
  return { prepared, preparedBytes, release };
}

async function rejectPublisher1PhaseB(continuationRoot) {
  const preparedPath = path.join(continuationRoot, 'publisher1-phase-b.prepared.json');
  const preparedBytes = await readFile(preparedPath);
  const prepared = JSON.parse(preparedBytes.toString('utf8'));
  assert.deepEqual(subject.canonicalJson(prepared), preparedBytes);
  const release = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER1_PHASE_B_BARRIER_RELEASE_V1',
    authority_sha: prepared.authority_sha,
    controller_generation_id: prepared.controller_generation_id,
    immutable_request_sha256: prepared.immutable_request_sha256,
    installed_self_sha256: prepared.installed_self_sha256,
    prepared_sha256: subject.sha256(preparedBytes),
    stage: prepared.stage,
    decision: 'REJECT',
    raw_values: false,
  };
  await writeOwnerOnlyFixture(
    path.join(continuationRoot, 'publisher1-phase-b.continue.json'), subject.canonicalJson(release),
  );
}

async function releasePublisher1DurableRegistration(continuationRoot, stage) {
  const slug = stage.toLowerCase();
  const preparedPath = path.join(
    continuationRoot, `publisher1-durable-registration-${slug}.prepared.json`,
  );
  const preparedBytes = await readFile(preparedPath);
  const prepared = JSON.parse(preparedBytes.toString('utf8'));
  assert.deepEqual(subject.canonicalJson(prepared), preparedBytes);
  assert.deepEqual(Object.keys(prepared).sort(), [
    'authority_sha', 'controller_generation_id', 'decision', 'immutable_request_sha256',
    'installed_self_sha256', 'purpose', 'raw_values', 'schema_version',
    'service_claim_sha256', 'service_definition_sha256', 'service_identity_sha256', 'stage',
  ]);
  assert.equal(prepared.schema_version, 1);
  assert.equal(prepared.purpose, 'CI3_SYNTHETIC_PUBLISHER1_DURABLE_REGISTRATION_BARRIER_V1');
  assert.equal(prepared.stage, stage);
  assert.equal(prepared.decision, 'PREPARED');
  assert.equal(prepared.raw_values, false);
  assert.match(prepared.authority_sha, /^[a-f0-9]{40}$/u);
  assert.match(prepared.controller_generation_id, /^controller-[a-f0-9]{64}$/u);
  for (const field of [
    'immutable_request_sha256', 'installed_self_sha256', 'service_claim_sha256',
    'service_definition_sha256', 'service_identity_sha256',
  ]) assert.match(prepared[field], /^[a-f0-9]{64}$/u);
  const release = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER1_DURABLE_REGISTRATION_BARRIER_RELEASE_V1',
    authority_sha: prepared.authority_sha,
    controller_generation_id: prepared.controller_generation_id,
    immutable_request_sha256: prepared.immutable_request_sha256,
    installed_self_sha256: prepared.installed_self_sha256,
    service_identity_sha256: prepared.service_identity_sha256,
    service_claim_sha256: prepared.service_claim_sha256,
    service_definition_sha256: prepared.service_definition_sha256,
    prepared_sha256: subject.sha256(preparedBytes),
    stage,
    decision: 'CONTINUE',
    raw_values: false,
  };
  await writeOwnerOnlyFixture(
    path.join(continuationRoot, `publisher1-durable-registration-${slug}.continue.json`),
    subject.canonicalJson(release),
  );
  return { prepared, preparedBytes, release };
}

async function releasePublisher1DurableWorker(continuationRoot, stage) {
  const slug = stage.toLowerCase().replaceAll('_', '-');
  const preparedPath = path.join(
    continuationRoot, `publisher1-durable-worker-${slug}.prepared.json`,
  );
  const preparedBytes = await readFile(preparedPath);
  const prepared = JSON.parse(preparedBytes.toString('utf8'));
  assert.deepEqual(subject.canonicalJson(prepared), preparedBytes);
  assert.deepEqual(Object.keys(prepared).sort(), [
    'authority_sha', 'controller_generation_id', 'decision', 'immutable_request_sha256',
    'installed_self_sha256', 'purpose', 'raw_values', 'schema_version',
    'service_claim_sha256', 'service_definition_sha256', 'service_identity_sha256', 'stage',
  ]);
  assert.equal(prepared.schema_version, 1);
  assert.equal(prepared.purpose, 'CI3_SYNTHETIC_PUBLISHER1_DURABLE_WORKER_BARRIER_V1');
  assert.equal(prepared.stage, stage);
  assert.equal(prepared.decision, 'PREPARED');
  assert.equal(prepared.raw_values, false);
  const release = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER1_DURABLE_WORKER_BARRIER_RELEASE_V1',
    authority_sha: prepared.authority_sha,
    controller_generation_id: prepared.controller_generation_id,
    immutable_request_sha256: prepared.immutable_request_sha256,
    installed_self_sha256: prepared.installed_self_sha256,
    service_identity_sha256: prepared.service_identity_sha256,
    service_claim_sha256: prepared.service_claim_sha256,
    service_definition_sha256: prepared.service_definition_sha256,
    prepared_sha256: subject.sha256(preparedBytes),
    stage,
    decision: 'CONTINUE',
    raw_values: false,
  };
  await writeOwnerOnlyFixture(
    path.join(continuationRoot, `publisher1-durable-worker-${slug}.continue.json`),
    subject.canonicalJson(release),
  );
  return { prepared, preparedBytes, release };
}

async function releasePublisher1Activation(continuationRoot, stage) {
  const slug = stage.toLowerCase().replaceAll('_', '-');
  const preparedPath = path.join(
    continuationRoot, `publisher1-durable-activation-${slug}.prepared.json`,
  );
  const preparedBytes = await readFile(preparedPath);
  const prepared = JSON.parse(preparedBytes.toString('utf8'));
  assert.deepEqual(subject.canonicalJson(prepared), preparedBytes);
  assert.deepEqual(Object.keys(prepared).sort(), [
    'authority_sha', 'controller_generation_id', 'decision', 'immutable_request_sha256',
    'installed_self_sha256', 'purpose', 'raw_values', 'schema_version',
    'service_claim_sha256', 'service_definition_sha256', 'service_identity_sha256', 'stage',
  ]);
  assert.equal(prepared.schema_version, 1);
  assert.equal(prepared.purpose, 'CI3_SYNTHETIC_PUBLISHER1_DURABLE_ACTIVATION_BARRIER_V1');
  assert.equal(prepared.stage, stage);
  assert.equal(prepared.decision, 'PREPARED');
  assert.equal(prepared.raw_values, false);
  const release = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER1_DURABLE_ACTIVATION_BARRIER_RELEASE_V1',
    authority_sha: prepared.authority_sha,
    controller_generation_id: prepared.controller_generation_id,
    immutable_request_sha256: prepared.immutable_request_sha256,
    installed_self_sha256: prepared.installed_self_sha256,
    service_identity_sha256: prepared.service_identity_sha256,
    service_claim_sha256: prepared.service_claim_sha256,
    service_definition_sha256: prepared.service_definition_sha256,
    prepared_sha256: subject.sha256(preparedBytes),
    stage,
    decision: 'CONTINUE',
    raw_values: false,
  };
  await writeOwnerOnlyFixture(
    path.join(continuationRoot, `publisher1-durable-activation-${slug}.continue.json`),
    subject.canonicalJson(release),
  );
  return { prepared, preparedBytes, release };
}

async function releasePublisher0TransportBarrier(sourceRoot, stage) {
  const barrierRoot = path.join(sourceRoot, 'publisher0-transport');
  const preparedPath = path.join(barrierRoot, `${stage}.prepared.json`);
  const preparedBytes = await readFile(preparedPath);
  const prepared = JSON.parse(preparedBytes.toString('utf8'));
  assert.deepEqual(subject.canonicalJson(prepared), preparedBytes);
  assert.deepEqual(Object.keys(prepared).sort(), [
    'decision', 'output_sha256', 'purpose', 'raw_values', 'request_sha256', 'schema_version', 'stage',
  ]);
  assert.equal(prepared.schema_version, 1);
  assert.equal(prepared.purpose, 'CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER_V1');
  assert.equal(prepared.stage, stage);
  assert.match(prepared.request_sha256, /^[0-9a-f]{64}$/);
  assert.match(prepared.output_sha256, /^[0-9a-f]{64}$/);
  assert.equal(prepared.decision, 'PREPARED');
  assert.equal(prepared.raw_values, false);
  const release = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER_RELEASE_V1',
    stage,
    request_sha256: prepared.request_sha256,
    output_sha256: prepared.output_sha256,
    prepared_sha256: subject.sha256(preparedBytes),
    decision: 'CONTINUE',
    raw_values: false,
  };
  await writeOwnerOnlyFixture(
    path.join(barrierRoot, `${stage}.continue.json`), subject.canonicalJson(release),
  );
  return { prepared, preparedBytes, release };
}

async function publisher0LifecycleDiagnostic(sourceRoot) {
  const transportRoot = path.join(sourceRoot, 'publisher0-transport');
  const result = {};
  for (const name of [
    'started', 'journal-prefix-synced', 'journal-complete', 'ack-observed', 'ack-sent',
    'ack-flushed', 'remote-closed', 'completed', 'quiesced', 'failed',
  ]) {
    const file = path.join(transportRoot, `${name}.json`);
    try {
      const value = JSON.parse((await readFile(file)).toString('utf8'));
      result[name] = {
        ...(typeof value.state === 'string' ? { state: value.state } : {}),
        ...(typeof value.failure_stage === 'string' ? { failure_stage: value.failure_stage } : {}),
        ...(typeof value.remote_failure_class === 'string' ? { remote_failure_class: value.remote_failure_class } : {}),
        ...(Object.hasOwn(value, 'status') ? { status: value.status } : {}),
        ...(Object.hasOwn(value, 'signal') ? { signal: value.signal } : {}),
        ...(typeof value.failure_class === 'string' ? { failure_class: value.failure_class } : {}),
      };
    } catch (error) {
      if (error?.code !== 'ENOENT') result[name] = { malformed_or_unreadable: true };
    }
  }
  return result;
}

async function provisionFrozenWriterFixture(label) {
  const fixture = await createActualCliFixture(label, { frozenWriter: true });
  assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
  assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
  assert.equal(runActualCli(fixture.root, '--receive-vps-pass').status, 0);
  assert.equal(runActualCli(fixture.root, '--provision-mac-publisher1').status, 0);
  const requestPath = path.join(fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit,
    'publisher1-transaction.request.json');
  const requestBytes = await readFile(requestPath);
  const request = JSON.parse(requestBytes.toString('utf8'));
  const writer = path.join(fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
    `bootstrap-${fixture.context.authority.manifest_sha256}`, 'runtime', 'ci3-terminal-anchor-writer');
  return { fixture, requestPath, requestBytes, request, writer };
}

function invokeInstalledFrozenWriter(writer, requestBytes, extraEnvironment = {}) {
  return spawnSync(writer, ['--publisher1-transaction'], {
    input: requestBytes, encoding: 'utf8', timeout: 30_000, maxBuffer: 64 * 1024,
    env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin', ...extraEnvironment },
  });
}

for (const mode of [
  '--self-test', '--prepare', '--provision-vps-publisher0', '--receive-vps-pass',
  '--provision-mac-publisher1', '--verify-chain',
]) {
  test(`mode accepts the sole fixed argument ${mode}`, () => {
    assert.equal(subject.parseMode([mode]), mode);
  });
}

for (const [name, argv] of [
  ['empty', []], ['two modes', ['--prepare', '--verify-chain']], ['arbitrary path', ['--prepare', '/tmp/output']],
  ['help', ['--help']], ['unknown', ['--publish']], ['blank', ['']], ['double-dash', ['--']],
  ['prepare typo', ['--prepar']], ['receive typo', ['--receive-vps']], ['verify typo', ['--verify']],
  ['self-test suffix', ['--self-test=true']], ['prepare equals', ['--prepare=/tmp']], ['positional', ['prepare']],
  ['null', [null]], ['number', [1]], ['object', [{}]], ['nested', [['--prepare']]],
  ['newline', ['--prepare\n']], ['nul', ['--prepare\0']], ['space', [' --prepare']],
  ['trailing space', ['--prepare ']], ['uppercase', ['--PREPARE']], ['slash', ['/prepare']], ['dash', ['-prepare']],
]) {
  test(`mode rejects ${name}`, () => {
    assert.throws(() => subject.parseMode(argv), (error) => error?.code === 'MODE_INVALID');
  });
}

for (const [name, value, expected] of [
  ['sorts object keys', { z: 1, a: 2 }, '{"a":2,"z":1}\n'],
  ['sorts nested object keys', { z: { y: 1, a: 2 } }, '{"z":{"a":2,"y":1}}\n'],
  ['preserves array order', { a: [3, 2, 1] }, '{"a":[3,2,1]}\n'],
  ['preserves booleans', { a: false, b: true }, '{"a":false,"b":true}\n'],
  ['preserves null', { a: null }, '{"a":null}\n'],
  ['encodes strings', { a: 'value' }, '{"a":"value"}\n'],
  ['encodes integers', { a: 7 }, '{"a":7}\n'],
  ['encodes empty object', {}, '{}\n'],
  ['encodes empty array', [], '[]\n'],
  ['is deterministic', { c: 3, a: 1, b: 2 }, '{"a":1,"b":2,"c":3}\n'],
]) {
  test(`canonical JSON ${name}`, () => {
    assert.equal(subject.canonicalJson(value).toString('utf8'), expected);
  });
}

test('physical identity is the exact BigInt-safe tuple', () => {
  assert.equal(
    subject.physicalIdentitySha256({ uid: 501, gid: 20, mode: 384, nlink: 1, size: 7, mtime_ns: '9007199254740993', dev: '9007199254740995', ino: '9007199254740997' }),
    subject.sha256(Buffer.from('uid=501;gid=20;mode=384;nlink=1;size=7;mtime=9007199254740993;dev=9007199254740995;ino=9007199254740997')),
  );
});

for (const [label, mutate] of [
  ['unsafe uid', (value) => { value.uid = BigInt(Number.MAX_SAFE_INTEGER) + 1n; }],
  ['unsafe byte size', (value) => { value.size = BigInt(Number.MAX_SAFE_INTEGER) + 1n; }],
  ['signed mtime overflow', (value) => { value.mtimeNs = 1n << 63n; }],
  ['unsigned device overflow', (value) => { value.dev = 1n << 64n; }],
]) {
  test(`physical stat producer rejects ${label} outside the Node/Swift intersection`, () => {
    const stat = { uid: 501n, gid: 20n, mode: 0o100600n, nlink: 1n, size: 1n, mtimeNs: 1n, dev: 1n, ino: 1n };
    mutate(stat);
    assert.throws(() => subject.physicalFromStat(stat), (error) => error?.code === 'PHYSICAL_IDENTITY');
  });
}

test('closed environment contains only the four fixed variables', () => {
  assert.deepEqual(subject.CLOSED_ENVIRONMENT, { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' });
});

test('transport role set is the exact eleven public and operational inputs', () => {
  assert.equal(subject.TRANSPORT_ROLES.length, 11);
  assert.equal(new Set(subject.TRANSPORT_ROLES).size, 11);
  assert.equal(subject.TRANSPORT_ROLES.includes('issuer-private-key'), false);
});

test('Publisher1 role set is the exact sixteen leaves consumed by the frozen writer', () => {
  assert.equal(subject.PUBLISHER1_ROLES.length, 16);
  assert.equal(new Set(subject.PUBLISHER1_ROLES).size, 16);
});

test('successor P0 preparation has only its SSH bootstrap and no future Publisher1 candidate', () => {
  assert.deepEqual(subject.PREPARE_CANDIDATE_ROLES, ['ssh-config']);
  assert.equal(subject.PREPARE_CANDIDATE_ROLES.some((role) => [
    'node-runtime', 'controller', 'launcher-runtime', 'issuer', 'vps-pass',
    'publisher-input-manifest', 'human-authorization', 'publisher1-descriptor-request',
    'publisher1-receiver-root', 'publisher1-installer-authority',
  ].includes(role)), false);
  assert.equal(subject.PUBLISHER1_RECEIVER_ROLES.length, 15);
  assert.equal(subject.PUBLISHER1_RECEIVER_ROLES.includes('human-authorization'), false);
  assert.deepEqual(subject.PUBLISHER1_RECEIVER_ROLES, subject.PUBLISHER1_ROLES.filter((role) => role !== 'human-authorization'));
});

test('SSH trust role set is exactly five and contains no host value', () => {
  assert.deepEqual(subject.SSH_TRUST_ROLES, ['ssh-config', 'ssh-known-hosts', 'ssh-private-key', 'ssh-public-key', 'ssh-trust-descriptor']);
});

test('fixed provisioning SSH invocation is noninteractive and has one attempt', () => {
  const invocation = subject.buildFixedProvisioningSshInvocation({
    configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', remoteCommand: '/usr/local/libexec/agentempp/ci3/provision-publisher0-v1',
  });
  assert.equal(invocation.executable, '/usr/bin/ssh');
  assert.deepEqual(invocation.argv, ['-F', '/private/synthetic/ssh_config', '-o', 'BatchMode=yes', '-o', 'NumberOfPasswordPrompts=0', 'ci3-publisher0', '/usr/local/libexec/agentempp/ci3/provision-publisher0-v1']);
  assert.equal(invocation.attempts, 1);
  assert.equal(invocation.retry, false);
});

test('fixed provisioning SSH invocation rejects an interactive remote command', () => {
  assert.throws(() => subject.buildFixedProvisioningSshInvocation({ configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', remoteCommand: '/bin/sh' }), (error) => error?.code === 'VPS_PUBLISHER0_PROVISION');
});

test('round3 Publisher0 single SSH starts from the exact Git-bound controller blob and carries one canonical bootstrap request', () => {
  const context = syntheticContext();
  const bootstrapInputs = Object.fromEntries(subject.TRANSPORT_ROLES.map((role) => [
    role, Buffer.from(`round3-authority-input-${role}\n`),
  ]));
  context.node_candidate_sha256 = subject.sha256(bootstrapInputs['node-runtime']);
  context.operation_authority_sha256 = subject.sha256(bootstrapInputs['operation-authority']);
  context.authority.manifest_sha256 = subject.sha256(bootstrapInputs['authority-manifest']);
  context.authority.components.controller = {
    path: 'scripts/ci3/ci3-bridge-controller.mjs', blob_oid: subject.gitBlobOid(bootstrapInputs.controller),
    sha256: subject.sha256(bootstrapInputs.controller),
  };
  context.authority.components.launcher = {
    path: 'scripts/ci3/ci3-bridge-launcher.zsh', blob_oid: subject.gitBlobOid(bootstrapInputs['launcher-runtime']),
    sha256: subject.sha256(bootstrapInputs['launcher-runtime']),
  };
  const invocation = subject.buildPublisher0GitBoundBootstrapInvocation({
    configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', context, bootstrapInputs,
  });
  assert.equal(invocation.executable, '/usr/bin/ssh');
  assert.deepEqual(invocation.argv.slice(0, 7), [
    '-F', '/private/synthetic/ssh_config', '-o', 'BatchMode=yes', '-o', 'NumberOfPasswordPrompts=0', 'ci3-publisher0',
  ]);
  assert.match(invocation.argv[7], /^exec \/usr\/bin\/env -i HOME=\/var\/empty LANG=C LC_ALL=C PATH=\/usr\/bin:\/bin \/bin\/sh -s -- [a-f0-9]{64}$/);
  assert.equal(invocation.attempts, 1);
  assert.equal(invocation.retry, false);
  assert.equal(invocation.input_sha256, subject.sha256(invocation.input));
  assert.equal(invocation.input.includes(Buffer.from(bootstrapInputs.controller.toString('base64'))), true);
  assert.equal(invocation.input.includes(Buffer.from(bootstrapInputs['launcher-runtime'].toString('base64'))), true);
  assert.equal(invocation.input.includes(Buffer.from(context.authority.components.controller.blob_oid)), true);
  assert.equal(invocation.input.includes(Buffer.from(context.authority.components.launcher.blob_oid)), true);
  assert.equal(invocation.argv.join(' ').includes('/usr/local/libexec/'), false);
});

test('round4 Publisher0 single SSH begins with the fixed system shell and transports every exact authority input in stdin', () => {
  const context = syntheticContext();
  const bootstrapInputs = Object.fromEntries(subject.TRANSPORT_ROLES.map((role) => [
    role, Buffer.from(`round4-authority-input-${role}\n`),
  ]));
  context.node_candidate_sha256 = subject.sha256(bootstrapInputs['node-runtime']);
  context.operation_authority_sha256 = subject.sha256(bootstrapInputs['operation-authority']);
  context.authority.components.controller = {
    path: 'scripts/ci3/ci3-bridge-controller.mjs',
    blob_oid: subject.gitBlobOid(bootstrapInputs.controller),
    sha256: subject.sha256(bootstrapInputs.controller),
  };
  context.authority.components.launcher = {
    path: 'scripts/ci3/ci3-bridge-launcher.zsh',
    blob_oid: subject.gitBlobOid(bootstrapInputs['launcher-runtime']),
    sha256: subject.sha256(bootstrapInputs['launcher-runtime']),
  };
  context.authority.manifest_sha256 = subject.sha256(bootstrapInputs['authority-manifest']);

  const invocation = subject.buildPublisher0GitBoundBootstrapInvocation({
    configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', context, bootstrapInputs,
  });

  assert.equal(invocation.executable, '/usr/bin/ssh');
  assert.match(invocation.argv[7], /^exec \/usr\/bin\/env -i HOME=\/var\/empty LANG=C LC_ALL=C PATH=\/usr\/bin:\/bin \/bin\/sh -s -- [a-f0-9]{64}$/);
  assert.equal(invocation.argv[7].includes('/var/lib/agentempp/ci3-authority-objects/'), false);
  assert.equal(invocation.argv[7].includes('ci3-bridge-controller.mjs'), false);
  assert.equal(invocation.input_sha256, subject.sha256(invocation.input));
  const commitBody = /commit_remote\(\) \{\n([\s\S]*?)\n\}/u.exec(invocation.input.toString('utf8'))?.[1];
  assert.equal(typeof commitBody, 'string');
  assert.deepEqual(
    commitBody.split('\n').map((line) => line.trim()).filter((line) =>
      /^(?:\/bin\/(?:ln|rm|chmod)|\/usr\/bin\/chattr|(?:\/usr)?\/bin\/sync)\b/u.test(line)),
    [
      '/bin/ln "$prepared_output_path" "$output_path"',
      '/bin/sync -f "$transaction_root"',
    ],
  );
  assert.equal(commitBody.trim().endsWith(
    'printf "CI3_REMOTE_COMMIT_DECISION_V1 %s %s\\n" "$output_sha" "$request_sha" >&2',
  ), true);
  for (const bytes of Object.values(bootstrapInputs)) {
    assert.equal(invocation.input.includes(Buffer.from(bytes.toString('base64'))), true);
  }
  for (const forbidden of ['issuer-signing-key', 'operation-authority.pass', 'unsigned-request', 'transport-receipt']) {
    assert.equal(invocation.input.includes(Buffer.from(forbidden)), false);
  }
  assert.equal(invocation.attempts, 1);
  assert.equal(invocation.retry, false);
});

test('round4 fake remote begins empty and the sole production-shaped stdin creates the claim-first Publisher0 transaction', async () => {
  const fakeRemoteParent = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-round4-empty-remote-')));
  const fakeRemoteRoot = path.join(fakeRemoteParent, 'root');
  try {
    await assert.rejects(lstat(fakeRemoteRoot), (error) => error?.code === 'ENOENT');
    const context = syntheticContext();
    const bindings = syntheticBindings();
    context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
    context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
    context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
    context.authority.subject_sha256 = subject.sha256(Buffer.from(controllerContract.AUTHORITY_SUBJECT));
    const writerSourceBytes = await readFile(WRITER_SOURCE);
    const controllerBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-controller.mjs', import.meta.url)));
    const launcherBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-launcher.zsh', import.meta.url)));
    const nodeBytes = Buffer.from(`#!/bin/sh\nexec ${JSON.stringify(process.execPath)} "$@"\n`);
    const { transportBytes: bootstrapInputs } = buildSemanticPublisherOutputs(context, writerSourceBytes, {
      authorityInputsOnly: true, nodeBytes, controllerBytes, launcherBytes,
    });
    const invocation = subject.buildPublisher0GitBoundBootstrapInvocation({
      configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', context,
      bootstrapInputs, syntheticRemoteRoot: fakeRemoteRoot, durableTransport: false,
    });

    const remote = spawnSync('/bin/sh', ['-c', invocation.argv[7]], {
      input: invocation.input, encoding: null, timeout: 30_000, maxBuffer: 16 * 1024 * 1024,
      env: { PATH: '/usr/bin:/bin' },
    });
    assert.equal(remote.status, 0, Buffer.from(remote.stderr ?? []).toString('utf8'));
    assert.equal(
      Buffer.from(remote.stderr).toString('utf8'),
      `CI3_REMOTE_COMMIT_DECISION_V1 ${subject.sha256(Buffer.from(remote.stdout))} ${invocation.request_sha256}\n`,
    );
    const authenticated = JSON.parse(Buffer.from(remote.stdout).toString('utf8'));
    assert.deepEqual(subject.canonicalJson(authenticated), Buffer.from(remote.stdout));
    assert.equal(subject.validateAuthenticatedPublisher0Output(authenticated, context).pass.authority_sha, context.authority.commit);

    const objectRoot = path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-authority-objects', context.authority.commit);
    assert.equal((await lstat(path.join(objectRoot, 'runtime', `node-${context.node_candidate_sha256}`))).mode & 0o777, 0o555);
    assert.equal((await lstat(path.join(objectRoot, 'git', context.authority.components.controller.blob_oid, 'ci3-bridge-controller.mjs'))).mode & 0o777, 0o555);
    const transactionBase = path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority', context.authority.commit);
    const generations = await readdir(transactionBase);
    assert.equal(generations.length, 1);
    const transactionRoot = path.join(transactionBase, generations[0]);
    const expected = [
      'publisher0.claim.json', 'issuer-signing-key.pkcs8', 'issuer-authority.receipt.json',
      'vps-operation-authority.unsigned.json', 'publisher-input', 'vps-operation-authority.pass.json',
      'publisher-input-manifest.json', 'authenticated-publisher0-output.prepared.json',
      'authenticated-publisher0-output.json',
    ];
    assert.deepEqual((await readdir(transactionRoot)).sort(), expected.sort());
    const prepared = await lstat(
      path.join(transactionRoot, 'authenticated-publisher0-output.prepared.json'), { bigint: true },
    );
    const committed = await lstat(
      path.join(transactionRoot, 'authenticated-publisher0-output.json'), { bigint: true },
    );
    assert.equal(prepared.dev, committed.dev);
    assert.equal(prepared.ino, committed.ino);
    assert.equal(prepared.nlink, 2n);
    assert.equal(committed.nlink, 2n);
    assert.equal((await lstat(path.join(transactionRoot, 'issuer-signing-key.pkcs8'))).mode & 0o777, 0o400);
    assert.equal((await readdir(path.join(transactionRoot, 'publisher-input'))).length, 11);
  } finally {
    await cleanupSyntheticFixture(fakeRemoteParent);
  }
});

test('round6 Publisher0 fixed primitive rejects an unclaimed preexisting object root without metadata mutation', async () => {
  const fakeRemoteParent = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-round6-unclaimed-object-root-')));
  const fakeRemoteRoot = path.join(fakeRemoteParent, 'root');
  try {
    const context = syntheticContext();
    const bindings = syntheticBindings();
    context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
    context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
    context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
    context.authority.subject_sha256 = subject.sha256(Buffer.from(controllerContract.AUTHORITY_SUBJECT));
    const writerSourceBytes = await readFile(WRITER_SOURCE);
    const controllerBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-controller.mjs', import.meta.url)));
    const launcherBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-launcher.zsh', import.meta.url)));
    const nodeBytes = Buffer.from(`#!/bin/sh\nexec ${JSON.stringify(process.execPath)} "$@"\n`);
    const { transportBytes: bootstrapInputs } = buildSemanticPublisherOutputs(context, writerSourceBytes, {
      authorityInputsOnly: true, nodeBytes, controllerBytes, launcherBytes,
    });
    const objectRoot = path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-authority-objects', context.authority.commit);
    await mkdir(objectRoot, { recursive: true, mode: 0o700 });
    await writeFile(path.join(objectRoot, 'unclaimed.seed'), Buffer.from('unclaimed\n'), { flag: 'wx', mode: 0o600 });
    const before = await snapshotFixtureTree(objectRoot);
    const invocation = subject.buildPublisher0GitBoundBootstrapInvocation({
      configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', context,
      bootstrapInputs, syntheticRemoteRoot: fakeRemoteRoot, durableTransport: false,
    });

    const remote = spawnSync('/bin/sh', ['-c', invocation.argv[7]], {
      input: invocation.input, encoding: null, timeout: 30_000, maxBuffer: 16 * 1024 * 1024,
      env: { PATH: '/usr/bin:/bin' },
    });
    assert.notEqual(remote.status, 0);
    assert.equal(remote.stdout?.length ?? 0, 0);
    assert.deepEqual(await snapshotFixtureTree(objectRoot), before);
  } finally {
    await cleanupSyntheticFixture(fakeRemoteParent);
  }
});

for (const executableRole of ['node', 'controller']) {
test(`round6 Publisher0 hashes and executes the pinned ${executableRole} descriptor across an open-to-auth pathname swap`, async () => {
  const fakeRemoteParent = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-round6-pinned-open-auth-')));
  const fakeRemoteRoot = path.join(fakeRemoteParent, 'root');
  let remote;
  try {
    const context = syntheticContext();
    const bindings = syntheticBindings();
    context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
    context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
    context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
    context.authority.subject_sha256 = subject.sha256(Buffer.from(controllerContract.AUTHORITY_SUBJECT));
    const writerSourceBytes = await readFile(WRITER_SOURCE);
    const controllerBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-controller.mjs', import.meta.url)));
    const launcherBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-launcher.zsh', import.meta.url)));
    const nodeBytes = Buffer.from(`#!/bin/sh\nexec ${JSON.stringify(process.execPath)} "$@"\n`);
    const { transportBytes: bootstrapInputs } = buildSemanticPublisherOutputs(context, writerSourceBytes, {
      authorityInputsOnly: true, nodeBytes, controllerBytes, launcherBytes,
    });
    const invocation = subject.buildPublisher0GitBoundBootstrapInvocation({
      configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', context,
      bootstrapInputs, syntheticRemoteRoot: fakeRemoteRoot,
      syntheticBarrierStage: 'physical-freeze-readback',
      syntheticPrimitiveBarrierStage: 'opened-before-authentication', durableTransport: false,
    });
    remote = spawn('/bin/sh', ['-c', invocation.argv[7]], {
      env: { PATH: '/usr/bin:/bin' }, stdio: ['pipe', 'pipe', 'pipe'],
    });
    const completion = collectActualCli(remote);
    remote.stdin.end(invocation.input);

    const barrierRoot = path.join(fakeRemoteRoot, '.ci3-synthetic-barriers');
    const openedPath = path.join(barrierRoot, 'publisher0-primitive-opened-before-authentication.prepared.json');
    await waitForFixturePath(openedPath, remote, 3_000);
    const openedBytes = await readFile(openedPath);
    const opened = JSON.parse(openedBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(opened), openedBytes);
    assert.equal(opened.purpose, 'CI3_SYNTHETIC_PUBLISHER0_PRIMITIVE_BARRIER_V1');
    assert.equal(opened.stage, 'opened-before-authentication');
    assert.equal(opened.request_sha256, invocation.request_sha256);

    const objectRoot = path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-authority-objects', context.authority.commit);
    const executablePath = executableRole === 'node'
      ? path.join(objectRoot, 'runtime', `node-${context.node_candidate_sha256}`)
      : path.join(objectRoot, 'git', context.authority.components.controller.blob_oid, 'ci3-bridge-controller.mjs');
    const executableParent = path.dirname(executablePath);
    const replacementBytes = executableRole === 'node'
      ? Buffer.from('#!/bin/sh\nexit 99\n')
      : Buffer.from('throw new Error("replacement controller executed");\n');
    await chmod(executableParent, 0o755);
    await rename(executablePath, `${executablePath}.displaced`);
    await writeFile(executablePath, replacementBytes, { flag: 'wx', mode: 0o555 });
    await chmod(executableParent, 0o555);

    const openedRelease = {
      schema_version: 1,
      purpose: 'CI3_SYNTHETIC_PUBLISHER0_PRIMITIVE_BARRIER_RELEASE_V1',
      stage: opened.stage,
      request_sha256: opened.request_sha256,
      prepared_sha256: subject.sha256(openedBytes),
      decision: 'CONTINUE',
      raw_values: false,
    };
    await writeFile(
      path.join(barrierRoot, 'publisher0-primitive-opened-before-authentication.continue.json'),
      subject.canonicalJson(openedRelease), { flag: 'wx', mode: 0o600 },
    );

    const authenticatedPath = path.join(barrierRoot, 'publisher0-primitive-descriptors-authenticated.json');
    await waitForFixturePath(authenticatedPath, remote, 3_000);
    const authenticatedBytes = await readFile(authenticatedPath);
    const authenticated = JSON.parse(authenticatedBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(authenticated), authenticatedBytes);
    assert.deepEqual(authenticated, {
      controller_sha256: context.authority.components.controller.sha256,
      decision: 'AUTHENTICATED',
      node_sha256: context.node_candidate_sha256,
      purpose: 'CI3_SYNTHETIC_PUBLISHER0_PINNED_DESCRIPTOR_AUTHENTICATION_V1',
      raw_values: false,
      request_sha256: invocation.request_sha256,
      schema_version: 1,
    });
    const result = await completion;
    assert.notEqual(result.status, 0, result.stdout);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, '');
    await assert.rejects(lstat(path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority')), { code: 'ENOENT' });
  } finally {
    if (remote?.exitCode === null && remote?.signalCode === null) remote.kill('SIGKILL');
    await cleanupSyntheticFixture(fakeRemoteParent);
  }
});
}

for (const executableRole of ['node', 'controller']) {
test(`round6 Publisher0 rejects a ${executableRole} pathname swap between descriptor authentication and execution`, async () => {
  const fakeRemoteParent = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-round6-pinned-auth-exec-')));
  const fakeRemoteRoot = path.join(fakeRemoteParent, 'root');
  let remote;
  try {
    const context = syntheticContext();
    const bindings = syntheticBindings();
    context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
    context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
    context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
    context.authority.subject_sha256 = subject.sha256(Buffer.from(controllerContract.AUTHORITY_SUBJECT));
    const writerSourceBytes = await readFile(WRITER_SOURCE);
    const controllerBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-controller.mjs', import.meta.url)));
    const launcherBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-launcher.zsh', import.meta.url)));
    const nodeBytes = Buffer.from(`#!/bin/sh\nexec ${JSON.stringify(process.execPath)} "$@"\n`);
    const { transportBytes: bootstrapInputs } = buildSemanticPublisherOutputs(context, writerSourceBytes, {
      authorityInputsOnly: true, nodeBytes, controllerBytes, launcherBytes,
    });
    const invocation = subject.buildPublisher0GitBoundBootstrapInvocation({
      configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', context,
      bootstrapInputs, syntheticRemoteRoot: fakeRemoteRoot,
      syntheticBarrierStage: 'physical-freeze-readback',
      syntheticPrimitiveBarrierStage: 'authenticated-before-execution', durableTransport: false,
    });
    remote = spawn('/bin/sh', ['-c', invocation.argv[7]], {
      env: { PATH: '/usr/bin:/bin' }, stdio: ['pipe', 'pipe', 'pipe'],
    });
    const completion = collectActualCli(remote);
    remote.stdin.end(invocation.input);

    const barrierRoot = path.join(fakeRemoteRoot, '.ci3-synthetic-barriers');
    const preparedPath = path.join(barrierRoot, 'publisher0-primitive-authenticated-before-execution.prepared.json');
    await waitForFixturePath(preparedPath, remote, 3_000);
    const preparedBytes = await readFile(preparedPath);
    const prepared = JSON.parse(preparedBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(prepared), preparedBytes);
    assert.equal(prepared.stage, 'authenticated-before-execution');
    assert.equal(prepared.request_sha256, invocation.request_sha256);

    const objectRoot = path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-authority-objects', context.authority.commit);
    const executablePath = executableRole === 'node'
      ? path.join(objectRoot, 'runtime', `node-${context.node_candidate_sha256}`)
      : path.join(objectRoot, 'git', context.authority.components.controller.blob_oid, 'ci3-bridge-controller.mjs');
    const executableParent = path.dirname(executablePath);
    const replacementBytes = executableRole === 'node'
      ? Buffer.from('#!/bin/sh\nexit 99\n')
      : Buffer.from('throw new Error("replacement controller executed");\n');
    await chmod(executableParent, 0o755);
    await rename(executablePath, `${executablePath}.displaced`);
    await writeFile(executablePath, replacementBytes, { flag: 'wx', mode: 0o555 });
    await chmod(executableParent, 0o555);

    const release = {
      schema_version: 1,
      purpose: 'CI3_SYNTHETIC_PUBLISHER0_PRIMITIVE_BARRIER_RELEASE_V1',
      stage: prepared.stage,
      request_sha256: prepared.request_sha256,
      prepared_sha256: subject.sha256(preparedBytes),
      decision: 'CONTINUE',
      raw_values: false,
    };
    await writeFile(
      path.join(barrierRoot, 'publisher0-primitive-authenticated-before-execution.continue.json'),
      subject.canonicalJson(release), { flag: 'wx', mode: 0o600 },
    );

    const result = await completion;
    assert.notEqual(result.status, 0, result.stdout);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, '');
    await assert.rejects(lstat(path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority')), { code: 'ENOENT' });
  } finally {
    if (remote?.exitCode === null && remote?.signalCode === null) remote.kill('SIGKILL');
    await cleanupSyntheticFixture(fakeRemoteParent);
  }
});
}

test('round6 Publisher0 verifies the exact frozen tree before entering the pinned node descriptor', async () => {
  const fakeRemoteParent = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-round6-exact-tree-pre-node-')));
  const fakeRemoteRoot = path.join(fakeRemoteParent, 'root');
  const nodeEnteredPath = path.join(fakeRemoteParent, 'node-entered.marker');
  let remote;
  try {
    const context = syntheticContext();
    const bindings = syntheticBindings();
    context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
    context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
    context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
    context.authority.subject_sha256 = subject.sha256(Buffer.from(controllerContract.AUTHORITY_SUBJECT));
    const writerSourceBytes = await readFile(WRITER_SOURCE);
    const controllerBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-controller.mjs', import.meta.url)));
    const launcherBytes = await readFile(fileURLToPath(new URL('./ci3-bridge-launcher.zsh', import.meta.url)));
    const nodeBytes = Buffer.from([
      '#!/bin/sh',
      `printf entered > ${JSON.stringify(nodeEnteredPath)}`,
      `exec ${JSON.stringify(process.execPath)} "$@"`,
      '',
    ].join('\n'));
    const { transportBytes: bootstrapInputs } = buildSemanticPublisherOutputs(context, writerSourceBytes, {
      authorityInputsOnly: true, nodeBytes, controllerBytes, launcherBytes,
    });
    const invocation = subject.buildPublisher0GitBoundBootstrapInvocation({
      configPath: '/private/synthetic/ssh_config', destinationAlias: 'ci3-publisher0', context,
      bootstrapInputs, syntheticRemoteRoot: fakeRemoteRoot,
      syntheticBarrierStage: 'physical-freeze-readback',
      syntheticPrimitiveBarrierStage: 'authenticated-before-execution', durableTransport: false,
    });
    remote = spawn('/bin/sh', ['-c', invocation.argv[7]], {
      env: { PATH: '/usr/bin:/bin' }, stdio: ['pipe', 'pipe', 'pipe'],
    });
    const completion = collectActualCli(remote);
    remote.stdin.end(invocation.input);

    const barrierRoot = path.join(fakeRemoteRoot, '.ci3-synthetic-barriers');
    const preparedPath = path.join(barrierRoot, 'publisher0-primitive-authenticated-before-execution.prepared.json');
    await waitForFixturePath(preparedPath, remote, 3_000);
    const preparedBytes = await readFile(preparedPath);
    const prepared = JSON.parse(preparedBytes.toString('utf8'));
    const objectRoot = path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-authority-objects', context.authority.commit);
    const inputsRoot = path.join(objectRoot, 'inputs');
    await chmod(inputsRoot, 0o755);
    await writeFile(path.join(inputsRoot, 'unexpected.payload'), Buffer.from('unexpected\n'), { flag: 'wx', mode: 0o444 });
    await chmod(inputsRoot, 0o555);
    const release = {
      schema_version: 1,
      purpose: 'CI3_SYNTHETIC_PUBLISHER0_PRIMITIVE_BARRIER_RELEASE_V1',
      stage: prepared.stage,
      request_sha256: prepared.request_sha256,
      prepared_sha256: subject.sha256(preparedBytes),
      decision: 'CONTINUE',
      raw_values: false,
    };
    await writeFile(
      path.join(barrierRoot, 'publisher0-primitive-authenticated-before-execution.continue.json'),
      subject.canonicalJson(release), { flag: 'wx', mode: 0o600 },
    );

    const result = await completion;
    assert.notEqual(result.status, 0, result.stdout);
    assert.equal(result.stdout, '');
    await assert.rejects(lstat(nodeEnteredPath), { code: 'ENOENT' });
    await assert.rejects(lstat(path.join(fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority')), { code: 'ENOENT' });
  } finally {
    if (remote?.exitCode === null && remote?.signalCode === null) remote.kill('SIGKILL');
    await cleanupSyntheticFixture(fakeRemoteParent);
  }
});

test('round6 owner-only receipt publication never replaces a concurrently published destination', async () => {
  const root = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-round6-no-replace-receipt-')));
  try {
    const destination = path.join(root, 'causal-receipt.json');
    const intended = subject.canonicalJson({ decision: 'INTENDED', raw_values: false, schema_version: 1 });
    const concurrent = subject.canonicalJson({ decision: 'CONCURRENT', raw_values: false, schema_version: 1 });
    await assert.rejects(
      subject.publishOwnerOnlyReceiptNoReplace({
        file: destination,
        bytes: intended,
        beforePublish: async () => writeFile(destination, concurrent, { flag: 'wx', mode: 0o600 }),
      }),
      (error) => error?.code === 'STOP_PRE_AUTHORITY',
    );
    assert.deepEqual(await readFile(destination), concurrent);
    assert.equal((await lstat(destination)).nlink, 1);
    assert.deepEqual((await readdir(root)).filter((entry) => entry.endsWith('.publishing')), []);
  } finally {
    await cleanupSyntheticFixture(root);
  }
});

for (const [label, mutate] of [
  ['same-content file inode swap', async ({ controllerPath, controllerBytes }) => {
    const parent = path.dirname(controllerPath);
    await chmod(parent, 0o755);
    await rename(controllerPath, `${controllerPath}.displaced`);
    await writeFile(controllerPath, controllerBytes, { flag: 'wx', mode: 0o555 });
    await chmod(parent, 0o555);
  }],
  ['same-content controller directory swap', async ({ objectRoot, controllerPath, controllerBytes }) => {
    const gitRoot = path.join(objectRoot, 'git');
    const controllerRoot = path.dirname(controllerPath);
    await chmod(gitRoot, 0o755);
    await rename(controllerRoot, `${controllerRoot}.displaced`);
    await mkdir(controllerRoot, { mode: 0o755 });
    await writeFile(controllerPath, controllerBytes, { flag: 'wx', mode: 0o555 });
    await chmod(controllerRoot, 0o555);
    await chmod(gitRoot, 0o555);
  }],
  ['post-freeze executable mode mutation', async ({ controllerPath }) => {
    await chmod(controllerPath, 0o755);
  }],
  ['post-freeze extra tree leaf', async ({ objectRoot }) => {
    const inputsRoot = path.join(objectRoot, 'inputs');
    await chmod(inputsRoot, 0o755);
    await writeFile(path.join(inputsRoot, 'unexpected.payload'), Buffer.from('unexpected\n'), { flag: 'wx', mode: 0o444 });
    await chmod(inputsRoot, 0o555);
  }],
]) {
  test(`Publisher0 pinned physical boundary rejects ${label} before controller execution`, async () => {
    let fixture;
    try {
      fixture = await createPublisher0PhysicalRaceFixture(label.replaceAll(' ', '-'));
      await mutate(fixture);
      await writeFile(fixture.releasePath, fixture.releaseBytes, { flag: 'wx', mode: 0o600 });
      const result = await fixture.completion;
      assert.notEqual(result.status, 0, result.stdout);
      assert.equal(result.stdout, '');
      await assert.rejects(lstat(fixture.transactionBase), (error) => error?.code === 'ENOENT');
    } finally {
      if (fixture?.remote.exitCode === null && fixture?.remote.signalCode === null) fixture.remote.kill('SIGKILL');
      if (fixture?.fakeRemoteParent) await cleanupSyntheticFixture(fixture.fakeRemoteParent);
    }
  });
}

for (const [label, preseed] of [
  ['unclaimed empty root', async () => {}],
  ['unclaimed extra leaf', async (transactionRoot) => {
    await writeFile(path.join(transactionRoot, 'unexpected.seed'), Buffer.from('preseed\n'), { flag: 'wx', mode: 0o444 });
  }],
  ['unclaimed private key', async (transactionRoot) => {
    await writeFile(path.join(transactionRoot, 'issuer-signing-key.pkcs8'), Buffer.from('preseed-key\n'), { flag: 'wx', mode: 0o400 });
  }],
  ['unclaimed issuer', async (transactionRoot) => {
    await writeFile(path.join(transactionRoot, 'issuer-authority.receipt.json'), Buffer.from('{}\n'), { flag: 'wx', mode: 0o444 });
  }],
  ['unclaimed payload', async (transactionRoot) => {
    const payloadRoot = path.join(transactionRoot, 'publisher-input');
    await mkdir(payloadRoot, { mode: 0o700 });
    await writeFile(path.join(payloadRoot, 'controller.payload'), Buffer.from('preseed-payload\n'), { flag: 'wx', mode: 0o444 });
  }],
]) {
  test(`Publisher0 claim-first boundary rejects ${label} without mutation`, async () => {
    let fixture;
    try {
      fixture = await createPublisher0PhysicalRaceFixture(`claim-first-${label.replaceAll(' ', '-')}`);
      await mkdir(path.dirname(fixture.transactionRoot), { recursive: true, mode: 0o755 });
      await chmod(path.join(fixture.fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority'), 0o755);
      await chmod(path.dirname(fixture.transactionRoot), 0o755);
      await mkdir(fixture.transactionRoot, { mode: 0o700 });
      await preseed(fixture.transactionRoot);
      const preseedPayloadRoot = path.join(fixture.transactionRoot, 'publisher-input');
      const preseedPayloadStat = await lstat(preseedPayloadRoot).catch((error) => {
        if (error?.code === 'ENOENT') return null;
        throw error;
      });
      if (preseedPayloadStat?.isDirectory()) await chmod(preseedPayloadRoot, 0o555);
      await chmod(fixture.transactionRoot, 0o555);
      const before = await snapshotFixtureTree(fixture.transactionRoot);
      await writeFile(fixture.releasePath, fixture.releaseBytes, { flag: 'wx', mode: 0o600 });
      const result = await fixture.completion;
      assert.notEqual(result.status, 0, result.stdout);
      assert.equal(result.stdout, '');
      assert.deepEqual(await snapshotFixtureTree(fixture.transactionRoot), before);
    } finally {
      if (fixture?.remote.exitCode === null && fixture?.remote.signalCode === null) fixture.remote.kill('SIGKILL');
      if (fixture?.fakeRemoteParent) await cleanupSyntheticFixture(fixture.fakeRemoteParent);
    }
  });
}

test('frozen binding schema accepts the complete owner supplied shape', () => {
  assert.equal(subject.validateFrozenBindings(syntheticBindings()), true);
});

for (const key of Object.keys(syntheticBindings())) {
  test(`frozen binding rejects mutation of ${key}`, () => {
    const candidate = syntheticBindings();
    candidate[key] = key.endsWith('SUBJECT') ? '' : 'invalid';
    assert.throws(() => subject.validateFrozenBindings(candidate), (error) => error?.code === 'FROZEN_AUTHORITY');
  });
}

test('frozen binding rejects a missing key', () => {
  const candidate = syntheticBindings();
  delete candidate.AUTHORITY_BASE;
  assert.throws(() => subject.validateFrozenBindings(candidate), (error) => error?.code === 'FROZEN_AUTHORITY');
});

test('frozen binding rejects an extra key', () => {
  const candidate = { ...syntheticBindings(), EXTRA: H64 };
  assert.throws(() => subject.validateFrozenBindings(candidate), (error) => error?.code === 'FROZEN_AUTHORITY');
});

test('owner binding file must be owner-only, single-link, regular and no-follow', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-external-bindings-'));
  try {
    const file = path.join(root, 'authorities.json');
    await writeFile(file, subject.canonicalJson(syntheticBindings()), { mode: 0o600, flag: 'wx' });
    const loaded = await subject.loadFrozenBindings(file);
    assert.deepEqual(loaded, syntheticBindings());
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('owner binding file rejects group-readable mode', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-external-bindings-'));
  try {
    const file = path.join(root, 'authorities.json');
    await writeFile(file, subject.canonicalJson(syntheticBindings()), { mode: 0o640, flag: 'wx' });
    await chmod(file, 0o640);
    assert.equal((await lstat(file)).mode & 0o777, 0o640);
    await rejectCode('FROZEN_AUTHORITY', () => subject.loadFrozenBindings(file));
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('derived layout contains only authority-derived fixed roots', () => {
  const layout = subject.deriveAuthorityLayout(syntheticBindings(), '/synthetic-owner-root');
  assert.equal(layout.authority_root, path.join('/synthetic-owner-root', syntheticBindings().MAC_EXECUTOR_AUTHORITY_SHA));
  assert.equal(layout.publisher0_root.includes(syntheticBindings().MAC_EXECUTOR_AUTHORITY_SHA), true);
  assert.equal(layout.publisher1_bootstrap_root.includes(syntheticBindings().MAC_EXECUTOR_AUTHORITY_SHA), true);
  assert.equal(layout.raw_values, false);
});

for (const [caseIndex, unsafeRoot] of ['', 'relative', '/tmp/../escape', '/tmp/root\0bad', '/tmp/root\nbad'].entries()) {
  test(`derived layout rejects unsafe root case ${caseIndex + 1}`, () => {
    assert.throws(() => subject.deriveAuthorityLayout(syntheticBindings(), unsafeRoot), (error) => error?.code === 'PATH_AUTHORITY');
  });
}

test('issuer authority validates a real Ed25519 public key', () => {
  const { issuer } = buildIssuerAndPass();
  assert.equal(subject.validateVpsIssuerAuthority(issuer), true);
});

test('signed VPS pass verifies with its exact issuer and context', () => {
  const fixture = buildIssuerAndPass();
  assert.equal(subject.verifyVpsPass(fixture.pass, fixture.issuer, fixture.context), true);
});

for (const field of [
  'authority_sha', 'authority_parent', 'authority_tree', 'authority_subject_sha256',
  'authority_manifest_sha256', 'operation_authority_sha256', 'node_candidate_sha256',
  'collector_contracts_sha256', 'publisher_input_manifest_sha256', 'remote_generation_id',
  'controller_generation_id', 'transfer_payload_sha256', 'issuer_authority_sha256',
  'issuer_key_sha256', 'source_generation_id', 'attempt', 'retry', 'raw_values',
]) {
  test(`signed VPS pass rejects mutation of ${field}`, () => {
    const fixture = buildIssuerAndPass();
    const candidate = structuredClone(fixture.pass);
    candidate[field] = typeof candidate[field] === 'boolean' ? !candidate[field]
      : typeof candidate[field] === 'number' ? candidate[field] + 1
        : String(candidate[field]).replace(/^./, candidate[field][0] === '0' ? '1' : '0');
    assert.throws(() => subject.verifyVpsPass(candidate, fixture.issuer, fixture.context), (error) => error?.code === 'VPS_OPERATION_AUTHORITY_SIGNATURE');
  });
}

test('signed VPS pass rejects a swapped issuer', () => {
  const fixture = buildIssuerAndPass();
  const swapped = buildIssuerAndPass();
  assert.throws(() => subject.verifyVpsPass(fixture.pass, swapped.issuer, fixture.context), (error) => error?.code === 'VPS_OPERATION_AUTHORITY_SIGNATURE');
});

test('signed VPS pass rejects invalid signature bytes', () => {
  const fixture = buildIssuerAndPass();
  const candidate = structuredClone(fixture.pass);
  candidate.signature_base64 = Buffer.alloc(64, 7).toString('base64');
  assert.throws(() => subject.verifyVpsPass(candidate, fixture.issuer, fixture.context), (error) => error?.code === 'VPS_OPERATION_AUTHORITY_SIGNATURE');
});

test('private issuer key is not serializable into issuer, pass or manifest', () => {
  const fixture = buildIssuerAndPass();
  const serialized = Buffer.concat([
    subject.canonicalJson(fixture.issuer), subject.canonicalJson(fixture.pass), subject.canonicalJson(fixture.manifest),
  ]).toString('utf8');
  assert.doesNotMatch(serialized, /pkcs8|begin[\s_-]*private|private_key|secret/i);
});

test('publisher transport manifest accepts the exact ordered roles', () => {
  const fixture = buildIssuerAndPass();
  assert.equal(subject.validatePublisherInputManifest(fixture.manifest, fixture.context), true);
});

test('successor authenticated Publisher0 output binds issuer pass manifest and every captured transport byte', () => {
  const context = syntheticContext();
  const writerSourceBytes = Buffer.from('synthetic writer source\n');
  const fixture = buildSemanticPublisherOutputs(context, writerSourceBytes);
  const issuer = JSON.parse(fixture.issuerBytes.toString('utf8'));
  const pass = JSON.parse(fixture.passBytes.toString('utf8'));
  const manifest = JSON.parse(fixture.manifestBytes.toString('utf8'));
  const payloads = Object.fromEntries(subject.TRANSPORT_ROLES.map((role) => [role, fixture.bytesByRole[role]]));
  const output = subject.buildAuthenticatedPublisher0Output({ context, issuer, pass, transportManifest: manifest, payloads });
  const validated = subject.validateAuthenticatedPublisher0Output(output, context);
  assert.deepEqual(validated.payloads, payloads);
  assert.equal(validated.issuer.authority_sha, context.authority.commit);
  assert.equal(validated.pass.publisher_input_manifest_sha256, subject.sha256(subject.canonicalJson(manifest)));
  const changed = structuredClone(output);
  changed.payloads[0].bytes_base64 = Buffer.from('substituted\n').toString('base64');
  assert.throws(() => subject.validateAuthenticatedPublisher0Output(changed, context), (error) => error?.code === 'AUTHENTICATED_PUBLISHER0_OUTPUT');
});

test('successor human authorization is built only from an existing request and binds receiver installer provenance and one prompt', () => {
  const { context, issuer, manifest, pass } = buildIssuerAndPass();
  const receiver = syntheticReceiver();
  const receiverLeaves = subject.PUBLISHER1_RECEIVER_ROLES.map((role) => receiver.observations[role]);
  const installerProvenance = {
    git_path: 'scripts/ci3/ci3-publisher1-bootstrap-installer.swift',
    git_blob_oid: 'a'.repeat(40), source_sha256: 'b'.repeat(64),
    authority_manifest_sha256: context.authority.manifest_sha256,
    compile_authority_sha256: 'c'.repeat(64), expected_binary_sha256: 'd'.repeat(64),
  };
  const authorizationRequest = subject.buildHumanAuthorizationRequest({
    context, issuer, manifest, pass, receiverRoot: receiver.root, receiverRootIdentitySha256: 'e'.repeat(64),
    receiverLeaves, installerProvenance, promptSha256: 'f'.repeat(64),
  });
  const requestBytes = subject.canonicalJson(authorizationRequest);
  const requestPath = '/private/var/folders/synthetic/publisher1-human-authorization.request.json';
  const requestMetadata = {
    uid: 501, gid: 20, mode: 0o600, nlink: 1, size: requestBytes.length,
    mtime_ns: '1700000000000000000', dev: '700', ino: '701',
  };
  const authorizationRequestObservation = {
    role: 'human-authorization-request', path: requestPath, path_sha256: subject.sha256(Buffer.from(requestPath)),
    sha256: subject.sha256(requestBytes), ...requestMetadata,
    identity_sha256: subject.physicalIdentitySha256(requestMetadata),
  };
  const receipt = subject.buildHumanAuthorizationReceipt({
    context, issuer, manifest, pass, authorizationRequest, authorizationRequestObservation,
    receiverRoot: receiver.root, receiverRootIdentitySha256: 'e'.repeat(64), receiverLeaves,
    installerProvenance, promptSha256: 'f'.repeat(64),
    confirmation: { authorized_uid: 501, authorized_gid: 20, prompt_budget: 1, confirmation_sha256: '9'.repeat(64) },
  });
  assert.equal(subject.validateHumanAuthorizationReceipt(receipt, context, manifest, pass, {
    authorizationRequest, authorizationRequestObservation, receiverRoot: receiver.root,
    receiverRootIdentitySha256: 'e'.repeat(64), receiverLeaves, installerProvenance, promptSha256: 'f'.repeat(64),
  }), true);
  assert.equal(receipt.schema_version, 2);
  assert.equal(receipt.prompt_budget, 1);
  assert.equal(receipt.authorization_request_sha256, subject.sha256(requestBytes));
  assert.equal(receipt.receiver_leaves_sha256, subject.sha256(subject.canonicalJson(receiverLeaves)));
  const predecessor = structuredClone(receipt);
  delete predecessor.authorization_request_identity_sha256;
  assert.throws(() => subject.validateHumanAuthorizationReceipt(predecessor, context, manifest, pass, {
    authorizationRequest, authorizationRequestObservation, receiverRoot: receiver.root,
    receiverRootIdentitySha256: 'e'.repeat(64), receiverLeaves, installerProvenance, promptSha256: 'f'.repeat(64),
  }), (error) => error?.code === 'STOP_PRE_AUTHORITY');
});

test('successor current-user confirmation uses one fixed non-admin macOS prompt after the request', async () => {
  const requestPath = '/private/var/folders/synthetic/publisher1-human-authorization.request.json';
  let attempts = 0;
  let spawns = 0;
  let selected;
  const child = new EventEmitter();
  child.stdout = new EventEmitter(); child.stderr = new EventEmitter();
  child.exitCode = null; child.signalCode = null; child.kill = () => true;
  const result = await subject.runHumanAuthorizationBoundary({
    requestPath, requestSha256: 'a'.repeat(64), requestIdentitySha256: 'b'.repeat(64),
    persistAttempt: async () => { attempts += 1; return true; },
    spawn: (executable, argv, options) => {
      spawns += 1; selected = { executable, argv, options };
      queueMicrotask(() => {
        child.stdout.emit('data', Buffer.from('button returned:Authorize\n'));
        child.emit('close', 0);
      });
      return child;
    },
  });
  assert.equal(attempts, 1);
  assert.equal(spawns, 1);
  assert.equal(selected.executable, '/usr/bin/osascript');
  assert.deepEqual(selected.options.env, subject.CLOSED_ENVIRONMENT);
  assert.equal(selected.argv[0], '-e');
  assert.match(selected.argv[1], /display dialog/);
  assert.doesNotMatch(selected.argv.join(' '), /administrator privileges|password|credential|token/i);
  assert.equal(result.prompt_budget, 1);
  assert.equal(result.confirmation_sha256, subject.sha256(Buffer.from('button returned:Authorize\n')));
});

test('successor installer source binding comes from the independent Git manifest blob OID and not a mutable sidecar', () => {
  const context = syntheticContext();
  const installerSource = Buffer.from('synthetic reviewed installer source\n');
  const installerPath = 'scripts/ci3/ci3-publisher1-bootstrap-installer.swift';
  const manifestBytes = Buffer.from(subject.PUBLISHER_AUTHORITY_PATHS.map((entryPath, index) => {
    const bytes = entryPath === installerPath ? installerSource : Buffer.from(`authority-entry-${index}\n`);
    return `${entryPath} ${subject.gitBlobOid(bytes)} ${subject.sha256(bytes)}`;
  }).join('\n') + '\n');
  context.authority.manifest_sha256 = subject.sha256(manifestBytes);
  const binding = subject.deriveInstallerGitSourceBinding({ context, authorityManifestBytes: manifestBytes, installerSourceBytes: installerSource });
  assert.deepEqual(binding, {
    git_path: installerPath,
    git_blob_oid: subject.gitBlobOid(installerSource),
    source_sha256: subject.sha256(installerSource),
    authority_manifest_sha256: subject.sha256(manifestBytes),
  });
  const substituted = Buffer.concat([installerSource, Buffer.from('// substituted\n')]);
  assert.throws(() => subject.deriveInstallerGitSourceBinding({
    context, authorityManifestBytes: manifestBytes, installerSourceBytes: substituted,
  }), (error) => error?.code === 'INSTALLER_GIT_PROVENANCE');
  const oidDrift = Buffer.from(manifestBytes.toString('utf8').replace(subject.gitBlobOid(installerSource), '0'.repeat(40)));
  context.authority.manifest_sha256 = subject.sha256(oidDrift);
  assert.throws(() => subject.deriveInstallerGitSourceBinding({
    context, authorityManifestBytes: oidDrift, installerSourceBytes: installerSource,
  }), (error) => error?.code === 'INSTALLER_GIT_PROVENANCE');
});

test('successor Phase A has one fixed macOS privilege boundary after semantic preflight and never executes the candidate pathname', () => {
  const supervisorSource = Buffer.from('synthetic reviewed supervisor source\n');
  const invocation = subject.buildMacOsPrivilegedBootstrapInvocation({
    candidatePath: '/private/var/folders/synthetic/ci3-publisher1-bootstrap-installer',
    candidateSha256: 'a'.repeat(64),
    immutableRequestPath: '/private/var/folders/synthetic/publisher1-immutable-installer.request.json',
    immutableRequestSha256: 'b'.repeat(64),
    boundaryManifestPath: '/private/var/folders/synthetic/publisher1-privileged-boundary.request.json',
    boundaryManifestSha256: 'c'.repeat(64),
    supervisorSourceBase64: supervisorSource.toString('base64'),
    supervisorSourceSha256: subject.sha256(supervisorSource),
  });
  assert.equal(invocation.executable, '/usr/bin/osascript');
  assert.deepEqual(invocation.environment, subject.CLOSED_ENVIRONMENT);
  assert.equal(invocation.privilege_prompts, 1);
  assert.equal(invocation.attempt, 1);
  assert.equal(invocation.retry, false);
  assert.equal(invocation.candidate_path_execution, false);
  assert.equal(invocation.atomic_selection, 'FIXED_ROOT_SUPERVISOR_SINGLE_OPEN_COPY_EXEC');
  assert.equal(invocation.reobserves_before_target_write, true);
  assert.equal(invocation.supervisor_source_sha256, subject.sha256(supervisorSource));
  assert.equal(invocation.argv[0], '-e');
  assert.equal((invocation.argv[1].match(/with administrator privileges/g) ?? []).length, 1);
  assert.match(invocation.argv[1], /\/usr\/bin\/xcrun/);
  assert.match(invocation.argv[1], /--privileged-supervisor/);
  assert.doesNotMatch(invocation.argv[1], /ci3-publisher1-bootstrap-installer/);
  assert.deepEqual(invocation.argv.slice(2), [
    '/private/var/folders/synthetic/ci3-publisher1-bootstrap-installer', 'a'.repeat(64),
    '/private/var/folders/synthetic/publisher1-immutable-installer.request.json', 'b'.repeat(64),
    '/private/var/folders/synthetic/publisher1-privileged-boundary.request.json', 'c'.repeat(64),
  ]);
});

test('round3 verify crosses the exact installed Publisher1 launcher invocation without an administrative effect', async () => {
  const context = syntheticContext();
  const invocation = subject.buildInstalledPublisher1LauncherInvocation({ context });
  assert.equal(invocation.executable, path.join(
    '/Library/Application Support/Agentempp/ci3-publisher1-bootstrap', context.authority.commit,
    `bootstrap-${context.authority.manifest_sha256}`, 'runtime', 'ci3-bridge-launcher.zsh',
  ));
  assert.deepEqual(invocation.argv, ['publish-operation-authority']);
  assert.deepEqual(invocation.environment, subject.CLOSED_ENVIRONMENT);
  let spawned = 0;
  let selected;
  const child = new EventEmitter();
  child.stdout = new EventEmitter(); child.stderr = new EventEmitter();
  child.exitCode = null; child.signalCode = null; child.kill = () => true;
  const result = await subject.runBoundedFixedSubprocess({
    ...invocation,
    expectedExisting: async () => false,
    persistAttempt: async () => true,
    preflightExecutable: async () => true,
    spawn: (executable, argv, options) => {
      spawned += 1; selected = { executable, argv, options };
      queueMicrotask(() => child.emit('close', 0));
      return child;
    },
  });
  assert.equal(result.state, 'CREATED');
  assert.equal(spawned, 1);
  assert.equal(selected.executable, invocation.executable);
  assert.deepEqual(selected.argv, ['publish-operation-authority']);
  assert.deepEqual(selected.options.env, subject.CLOSED_ENVIRONMENT);
});

test('round3 macOS privileged invocation crosses the real bounded argv gate and fake spawn exactly once', async () => {
  const supervisorSource = Buffer.from('synthetic reviewed supervisor source\n');
  const invocation = subject.buildMacOsPrivilegedBootstrapInvocation({
    candidatePath: '/private/var/folders/synthetic/ci3-publisher1-bootstrap-installer',
    candidateSha256: 'a'.repeat(64),
    immutableRequestPath: '/private/var/folders/synthetic/publisher1-immutable-installer.request.json',
    immutableRequestSha256: 'b'.repeat(64),
    boundaryManifestPath: '/private/var/folders/synthetic/publisher1-privileged-boundary.request.json',
    boundaryManifestSha256: 'c'.repeat(64),
    supervisorSourceBase64: supervisorSource.toString('base64'),
    supervisorSourceSha256: subject.sha256(supervisorSource),
  });
  assert.equal(invocation.argv.every((value) => !/[\0\r\n]/.test(value)), true);
  assert.match(invocation.argv[1], /\/usr\/bin\/xcrun swift - --privileged-supervisor/);
  assert.doesNotMatch(invocation.argv[1], /swift - -- --privileged-supervisor/);
  assert.equal((invocation.argv[1].match(/with administrator privileges/g) ?? []).length, 1);

  let attempts = 0;
  let spawns = 0;
  let selected;
  const child = new EventEmitter();
  child.stdout = new EventEmitter(); child.stderr = new EventEmitter();
  child.exitCode = null; child.signalCode = null; child.kill = () => true;
  const result = await subject.runBoundedFixedSubprocess({
    ...invocation,
    expectedExisting: async () => false,
    persistAttempt: async () => { attempts += 1; return true; },
    spawn: (executable, argv, options) => {
      spawns += 1;
      selected = { executable, argv, options };
      queueMicrotask(() => child.emit('close', 0));
      return child;
    },
  });
  assert.equal(attempts, 1);
  assert.equal(spawns, 1);
  assert.equal(selected.executable, '/usr/bin/osascript');
  assert.deepEqual(selected.argv, invocation.argv);
  assert.deepEqual(selected.options.env, subject.CLOSED_ENVIRONMENT);
  assert.deepEqual(result, {
    state: 'CREATED', effect_executions: 1, stdout_bytes: 0, stderr_bytes: 0, raw_values: false,
  });
});

test('round3 Swift stdin interpreter dispatches privileged supervisor as the first user argument', () => {
  const probe = spawnSync('/usr/bin/xcrun', ['swift', '-', '--privileged-supervisor', 'sentinel'], {
    input: 'import Foundation\nlet values = Array(CommandLine.arguments.dropFirst())\nlet bytes = try! JSONSerialization.data(withJSONObject: values)\nFileHandle.standardOutput.write(bytes)\n',
    encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 30_000, maxBuffer: 64 * 1024,
  });
  assert.equal(probe.status, 0, probe.stderr);
  assert.deepEqual(JSON.parse(probe.stdout), ['--privileged-supervisor', 'sentinel']);
});

test('successor atomic privileged selector rejects a post-verification pathname swap with zero privileged candidate instructions and zero target writes', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-privileged-selector-race-'));
  try {
    const candidatePath = path.join(root, 'candidate');
    const displacedPath = path.join(root, 'candidate.displaced');
    const replacementPath = path.join(root, 'replacement');
    const reviewed = Buffer.from('reviewed-installer\n');
    await writeFile(candidatePath, reviewed, { flag: 'wx', mode: 0o700 });
    await writeFile(replacementPath, Buffer.from('replacement-installer\n'), { flag: 'wx', mode: 0o700 });
    let privilegedCandidateInstructions = 0;
    let targetWrites = 0;
    await rejectCode('STOP_PRE_AUTHORITY', () => subject.runAtomicInstallerSelectionGate({
      candidatePath,
      expectedSha256: subject.sha256(reviewed),
      afterVerification: async () => {
        await rename(candidatePath, displacedPath);
        await rename(replacementPath, candidatePath);
      },
      invokePrivilege: async () => {
        privilegedCandidateInstructions += 1;
        targetWrites += 1;
      },
    }));
    assert.equal(privilegedCandidateInstructions, 0);
    assert.equal(targetWrites, 0);
  } finally { await rm(root, { recursive: true, force: true }); }
});

for (const [index, role] of subject.TRANSPORT_ROLES.entries()) {
  test(`publisher transport rejects missing role ${role}`, () => {
    const fixture = buildIssuerAndPass();
    const candidate = structuredClone(fixture.manifest);
    candidate.entries.splice(index, 1);
    candidate.transfer_payload_sha256 = subject.sha256(subject.canonicalJson(candidate.entries));
    assert.throws(() => subject.validatePublisherInputManifest(candidate, fixture.context), (error) => error?.code === 'PUBLISHER_INPUT_MANIFEST');
  });

  test(`publisher transport rejects duplicate role ${role}`, () => {
    const fixture = buildIssuerAndPass();
    const candidate = structuredClone(fixture.manifest);
    candidate.entries[index === 0 ? 1 : 0] = structuredClone(candidate.entries[index]);
    candidate.transfer_payload_sha256 = subject.sha256(subject.canonicalJson(candidate.entries));
    assert.throws(() => subject.validatePublisherInputManifest(candidate, fixture.context), (error) => error?.code === 'PUBLISHER_INPUT_MANIFEST');
  });
}

for (const field of ['authority_sha', 'remote_generation_id', 'controller_generation_id', 'collector_contracts_sha256', 'raw_values']) {
  test(`publisher transport rejects wrong ${field}`, () => {
    const fixture = buildIssuerAndPass();
    const candidate = structuredClone(fixture.manifest);
    candidate[field] = field === 'raw_values' ? true : H64;
    assert.throws(() => subject.validatePublisherInputManifest(candidate, fixture.context), (error) => error?.code === 'PUBLISHER_INPUT_MANIFEST');
  });
}

test('materializer authority accepts the exact sixteen receiver leaves', () => {
  const context = syntheticContext();
  const receiver = syntheticReceiver();
  const authority = subject.buildPublisher1MaterializerAuthority({
    context,
    requestPath: '/private/var/folders/synthetic/publisher1.request.json',
    requestSha256: 'a'.repeat(64),
    requestObservation: { ...syntheticObservation('request', '/private/var/folders/synthetic', 20), path: '/private/var/folders/synthetic/publisher1.request.json', path_sha256: subject.sha256(Buffer.from('/private/var/folders/synthetic/publisher1.request.json')) },
    receiverRoot: receiver.root,
    receiverRootIdentitySha256: 'b'.repeat(64),
    receiverLeaves: Object.values(receiver.observations),
    issuerAuthoritySha256: 'c'.repeat(64),
    materializerSha256: 'd'.repeat(64),
    writerSourceSha256: context.authority.components.writer.sha256,
  });
  assert.equal(subject.validatePublisher1MaterializerAuthority(authority, context, {
    receiverRoot: receiver.root,
    receiverRootIdentitySha256: 'b'.repeat(64),
    receiverLeaves: Object.values(receiver.observations),
  }), true);
  assert.equal(authority.receiver_leaves.length, 16);
});

function materializerFixture() {
  const context = syntheticContext();
  const receiver = syntheticReceiver();
  const requestPath = '/private/var/folders/synthetic/publisher1.request.json';
  const requestObservation = syntheticObservation('request', '/private/var/folders/synthetic', 20);
  requestObservation.path = requestPath;
  requestObservation.path_sha256 = subject.sha256(Buffer.from(requestPath));
  return {
    context,
    expected: {
      receiverRoot: receiver.root,
      receiverRootIdentitySha256: 'b'.repeat(64),
      receiverLeaves: Object.values(receiver.observations),
    },
    authority: subject.buildPublisher1MaterializerAuthority({
      context, requestPath, requestSha256: 'a'.repeat(64), requestObservation,
      receiverRoot: receiver.root, receiverRootIdentitySha256: 'b'.repeat(64),
      receiverLeaves: Object.values(receiver.observations), issuerAuthoritySha256: 'c'.repeat(64),
      materializerSha256: 'd'.repeat(64), writerSourceSha256: context.authority.components.writer.sha256,
    }),
  };
}

for (const [index, role] of subject.PUBLISHER1_ROLES.entries()) {
  test(`materializer rejects missing receiver leaf ${role}`, () => {
    const fixture = materializerFixture();
    fixture.authority.receiver_leaves.splice(index, 1);
    assert.throws(() => subject.validatePublisher1MaterializerAuthority(fixture.authority, fixture.context, fixture.expected), (error) => error?.code === 'STOP_PRE_AUTHORITY');
  });

  test(`materializer rejects duplicated receiver leaf ${role}`, () => {
    const fixture = materializerFixture();
    fixture.authority.receiver_leaves[index === 0 ? 1 : 0] = structuredClone(fixture.authority.receiver_leaves[index]);
    assert.throws(() => subject.validatePublisher1MaterializerAuthority(fixture.authority, fixture.context, fixture.expected), (error) => error?.code === 'STOP_PRE_AUTHORITY');
  });
}

for (const field of ['uid', 'gid', 'mode', 'nlink', 'size', 'mtime_ns', 'dev', 'ino', 'identity_sha256', 'path_sha256', 'sha256']) {
  test(`materializer rejects receiver physical drift ${field}`, () => {
    const fixture = materializerFixture();
    fixture.authority.receiver_leaves[0][field] = field === 'mode' ? 0o644 : field === 'nlink' ? 2 : field.endsWith('sha256') ? H64 : -1;
    assert.throws(() => subject.validatePublisher1MaterializerAuthority(fixture.authority, fixture.context, fixture.expected), (error) => error?.code === 'STOP_PRE_AUTHORITY');
  });
}

test('zero-retry operation calls its adapter exactly once on failure', async () => {
  let attempts = 0;
  await rejectCode('SYNTHETIC_FAILURE', () => subject.runZeroRetryOperation(async () => {
    attempts += 1;
    const error = new Error('synthetic');
    error.code = 'SYNTHETIC_FAILURE';
    throw error;
  }, { timeoutMs: 1000, code: 'SYNTHETIC_FAILURE' }));
  assert.equal(attempts, 1);
});

test('zero-retry operation times out once without retry', async () => {
  let attempts = 0;
  await rejectCode('TIMEOUT', () => subject.runZeroRetryOperation(async () => {
    attempts += 1;
    await new Promise((resolve) => setTimeout(resolve, 40));
  }, { timeoutMs: 5, code: 'TIMEOUT' }));
  assert.equal(attempts, 1);
});

test('synthetic prepare writes only an owner-only sealed helper input and delegates candidate materialization', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-external-prepare-'));
  try {
    let sealedRequest;
    const bindings = syntheticBindings();
    const context = syntheticContext();
    context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
    context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
    context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
    const candidates = Object.fromEntries(subject.PREPARE_CANDIDATE_ROLES.map((role) => [role, Buffer.from(`synthetic-${role}\n`)]));
    const result = await subject.runPrepare({ bindings, context, ownerRoot: root, candidates, gate0Receipt: {
      schema_version: 1, purpose: 'CI3_MAC_GATE0_LAUNCH_ATTESTATION_V1', executor_authority_sha: bindings.MAC_EXECUTOR_AUTHORITY_SHA,
      executor_authority_parent: bindings.MAC_EXECUTOR_AUTHORITY_PARENT, executor_authority_tree: bindings.MAC_EXECUTOR_AUTHORITY_TREE,
      executor_authority_manifest_sha256: context.authority.manifest_sha256, launcher_sha256: context.authority.components.launcher.sha256,
      exit_code: 0, stdout_bytes: 0, stderr_bytes: 0, status: 'PASS', previous_gate0_receipt_preserved: true,
      pre_gate0_git_fetch_attempts_new_authority: 0, pre_gate0_operational_network_attempts: 0,
      pre_gate0_simulator_attempts: 0, pre_gate0_ssh_g_attempts: 0,
    }, promptSha256: 'f'.repeat(64), localPrepare: async ({ environment, helper_path, request_bytes, request_sha256 }) => {
      assert.deepEqual(environment, subject.CLOSED_ENVIRONMENT);
      assert.match(helper_path, /ci3-publisher1-bootstrap-installer\.swift$/);
      assert.equal(Buffer.isBuffer(request_bytes), true);
      assert.match(request_sha256, /^[a-f0-9]{64}$/);
      sealedRequest = request_bytes;
      return true;
    } });
    assert.equal(result.state, 'PREPARED');
    assert.equal(result.raw_values, false);
    const request = JSON.parse(sealedRequest.toString('utf8'));
    assert.equal(request.purpose, 'CI3_PUBLISHER1_LOCAL_PREPARE_V1');
    assert.deepEqual(request.candidates.map(({ role }) => role), subject.PREPARE_CANDIDATE_ROLES);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('synthetic verify-chain preserves bundle values and orders controller after Publisher1', async () => {
  const events = [];
  const result = await subject.verifyChain({
    expected: { remote_bundle_unchanged: true, gate0_preserved: true },
    adapters: {
      verifyPublisher0: async () => { events.push('publisher0'); return true; },
      verifyTransport: async () => { events.push('transport'); return true; },
      verifyPublisher1: async () => { events.push('publisher1'); return true; },
      verifyControllerReadback: async () => { events.push('controller'); return true; },
    },
  });
  assert.deepEqual(events, ['publisher0', 'transport', 'publisher1', 'controller']);
  assert.deepEqual(result, { state: 'CHAIN_VERIFIED', raw_values: false });
});

test('self-test is synthetic and reports no network, admin, simulator or root writes', async () => {
  const result = await subject.runSelfTest();
  assert.equal(result.state, 'SELF_TEST_PASS');
  assert.equal(result.network_calls, 0);
  assert.equal(result.admin_prompts, 0);
  assert.equal(result.simulator_executions, 0);
  assert.equal(result.root_writes, 0);
  assert.equal(result.raw_values, false);
});

test('verify-chain stops before transport when Publisher0 verification fails', async () => {
  const events = [];
  await rejectCode('CHAIN_VERIFY', () => subject.verifyChain({
    expected: { remote_bundle_unchanged: true, gate0_preserved: true },
    adapters: {
      verifyPublisher0: async () => { events.push('publisher0'); return false; },
      verifyTransport: async () => { events.push('transport'); return true; },
      verifyPublisher1: async () => { events.push('publisher1'); return true; },
      verifyControllerReadback: async () => { events.push('controller'); return true; },
    },
  }));
  assert.deepEqual(events, ['publisher0']);
});

test('prepare rejects a Gate 0 receipt that lost its preserved marker', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-external-prepare-gate0-'));
  try {
    const bindings = syntheticBindings();
    const context = syntheticContext();
    context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
    context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
    context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
    const candidates = Object.fromEntries(subject.PREPARE_CANDIDATE_ROLES.map((role) => [role, Buffer.from(`synthetic-${role}\n`)]));
    await rejectCode('GATE0_PRESERVATION', () => subject.runPrepare({
      bindings, context, ownerRoot: root, candidates, gate0Receipt: {
        schema_version: 1, purpose: 'CI3_MAC_GATE0_LAUNCH_ATTESTATION_V1', executor_authority_sha: bindings.MAC_EXECUTOR_AUTHORITY_SHA,
        executor_authority_parent: bindings.MAC_EXECUTOR_AUTHORITY_PARENT, executor_authority_tree: bindings.MAC_EXECUTOR_AUTHORITY_TREE,
        executor_authority_manifest_sha256: context.authority.manifest_sha256, launcher_sha256: context.authority.components.launcher.sha256,
        exit_code: 0, stdout_bytes: 0, stderr_bytes: 0, status: 'PASS', previous_gate0_receipt_preserved: false,
        pre_gate0_git_fetch_attempts_new_authority: 0, pre_gate0_operational_network_attempts: 0,
        pre_gate0_simulator_attempts: 0, pre_gate0_ssh_g_attempts: 0,
      }, promptSha256: 'f'.repeat(64), localPrepare: async () => true }));
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('frozen binding file rejects a symbolic-link indirection', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-external-bindings-link-'));
  try {
    const target = path.join(root, 'target.json');
    const file = path.join(root, 'authorities.json');
    await writeFile(target, subject.canonicalJson(syntheticBindings()), { mode: 0o600, flag: 'wx' });
    await (await import('node:fs/promises')).symlink(target, file);
    await rejectCode('FROZEN_AUTHORITY', () => subject.loadFrozenBindings(file));
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('zero-retry operation returns the first successful adapter result', async () => {
  let attempts = 0;
  const result = await subject.runZeroRetryOperation(async () => {
    attempts += 1;
    return { status: 'synthetic-success' };
  }, { timeoutMs: 1000, code: 'SYNTHETIC_FAILURE' });
  assert.deepEqual(result, { status: 'synthetic-success' });
  assert.equal(attempts, 1);
});

test('round2 issuer is an exact raw Ed25519 frozen-consumer artifact', () => {
  const fixture = buildIssuerAndPass();
  assert.equal(fixture.issuer.public_key_algorithm, 'Ed25519');
  assert.equal(Buffer.from(fixture.issuer.public_key_raw_base64, 'base64').length, 32);
  assert.equal(fixture.issuer.allowed_pass_purpose, 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1');
  assert.equal(fixture.pass.purpose, 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1');
  assert.equal(fixture.pass.signed_payload_sha256, subject.sha256(subject.canonicalJson(Object.fromEntries(Object.entries(fixture.pass).filter(([key]) => key !== 'signature_base64' && key !== 'signed_payload_sha256')))));
});

test('round2 issuer rejects a non-Ed25519 public key', () => {
  const context = syntheticContext();
  const { publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  assert.throws(() => subject.buildVpsIssuerAuthority({
    authoritySha: context.authority.commit,
    issuerGenerationId: `issuer-${'9'.repeat(64)}`,
    publicKey,
  }), (error) => error?.code === 'VPS_ISSUER_AUTHORITY');
});

test('round2 pass signer must derive byte-identical issuer public key', () => {
  const fixture = buildIssuerAndPass();
  const { privateKey } = generateKeyPairSync('ed25519');
  const { signature_base64: _signature, ...unsigned } = fixture.pass;
  assert.throws(() => subject.signVpsPass({ unsigned, issuer: fixture.issuer, privateKey }), (error) => error?.code === 'VPS_OPERATION_AUTHORITY_SIGNATURE');
});

test('round2 materializer authority validates after canonical serialize and parse', () => {
  const fixture = materializerFixture();
  const persisted = JSON.parse(subject.canonicalJson(fixture.authority).toString('utf8'));
  assert.equal(subject.validatePublisher1MaterializerAuthority(persisted, fixture.context, fixture.expected), true);
});

test('round2 timeout aborts and waits for the sole operation to settle', async () => {
  let aborted = false;
  let settled = false;
  await rejectCode('TIMEOUT', () => subject.runZeroRetryOperation((signal) => new Promise((resolve) => {
    signal.addEventListener('abort', () => { aborted = true; settled = true; resolve(); }, { once: true });
  }), { timeoutMs: 5, code: 'ROUND2_OPERATION' }));
  assert.equal(aborted, true);
  assert.equal(settled, true);
});

for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass', '--provision-mac-publisher1', '--verify-chain']) {
  test(`round2 subprocess dispatches ${mode} to its bounded pre-authority stop`, () => {
    const result = spawnSync(process.execPath, [CHAIN_SCRIPT, mode], {
      encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: process.env.PATH ?? '/usr/bin:/bin' },
    });
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, `STOP_PRE_AUTHORITY mode=${mode} raw_values=false\n`);
  });
}

test('round3 actual main stops before spawning a synthetic fixed executable when its owner-only authority set is incomplete', async () => {
  const fixture = await createActualCliFixture('pre-authority-stop');
  try {
    await rm(path.join(fixture.sourceRoot, 'gate0.json'));
    const result = runActualCli(fixture.root, '--receive-vps-pass');
    assert.equal(result.status, 1);
    assert.equal(result.stderr, 'STOP_PRE_AUTHORITY mode=--receive-vps-pass raw_values=false\n');
    await assert.rejects(lstat(path.join(fixture.root, 'fixed-bin', 'receive-vps-pass.ran')));
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round3 pre-materializer creates the unchanged frozen sixteen-leaf descriptor transaction and recovers only exact-existing objects', async () => {
  const root = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-pre-materializer-')));
  try {
    const context = syntheticContext();
    const manifest = '9'.repeat(64);
    const receiverRoot = path.join(root, 'receiver', context.generations.remote, context.generations.controller, manifest);
    const requestPath = path.join(root, 'publisher1-transaction.request.json');
    await mkdir(receiverRoot, { recursive: true, mode: 0o700 });
    const bytesByRole = Object.fromEntries(subject.PUBLISHER1_ROLES.map((role, index) => [role, Buffer.from(`pre-${index}\n`)]));
    const first = await subject.preMaterializeFrozenControllerTransaction({
      context, receiverRoot, receiverManifestSha256: manifest, requestPath, bytesByRole,
    });
    const before = await lstat(requestPath, { bigint: true });
    const second = await subject.preMaterializeFrozenControllerTransaction({
      context, receiverRoot, receiverManifestSha256: manifest, requestPath, bytesByRole,
    });
    const after = await lstat(requestPath, { bigint: true });
    assert.equal(first.transaction.purpose, 'CI3_PUBLISHER1_DESCRIPTOR_TRANSACTION_V1');
    assert.equal(first.transaction.entries.length, 16);
    assert.equal(second.state, 'PREMATERIALIZED_EXACT_EXISTING');
    assert.equal(before.dev, after.dev);
    assert.equal(before.ino, after.ino);
    const requestPhysical = subject.physicalFromStat(after);
    const leaves = await Promise.all(subject.PUBLISHER1_ROLES.map(async (role) => {
      const leafPath = path.join(receiverRoot, `${role}.payload`);
      const bytes = await readFile(leafPath);
      const physical = subject.physicalFromStat(await lstat(leafPath, { bigint: true }));
      return { role, path: leafPath, path_sha256: subject.sha256(Buffer.from(leafPath)), sha256: subject.sha256(bytes),
        ...physical, identity_sha256: subject.physicalIdentitySha256(physical) };
    }));
    const issuerBytes = subject.canonicalJson({ schema_version: 1, purpose: 'synthetic-issuer' });
    const materializer = subject.buildPublisher1MaterializerAuthority({
      context, requestPath, requestSha256: first.transaction_sha256,
      requestObservation: { role: 'request', path: requestPath, path_sha256: subject.sha256(Buffer.from(requestPath)),
        sha256: first.transaction_sha256, ...requestPhysical, identity_sha256: subject.physicalIdentitySha256(requestPhysical) },
      receiverRoot, receiverRootIdentitySha256: subject.physicalIdentitySha256(subject.physicalFromStat(await lstat(receiverRoot, { bigint: true }))),
      receiverLeaves: leaves, issuerAuthoritySha256: subject.sha256(issuerBytes), materializerSha256: context.authority.components.writer.sha256,
      writerSourceSha256: context.authority.components.writer.sha256,
    });
    assert.deepEqual(await subject.validatePreMaterializedControllerTransaction({
      context, issuerBytes, materializer, requestPath, receiverRoot,
    }), { state: 'FROZEN_CONTROLLER_ACCEPTS', raw_values: false });
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('round4 derives the exact frozen-controller publisher request and receiver locations', () => {
  const context = syntheticContext();
  const originalHome = process.env.HOME;
  try {
    process.env.HOME = '/private/ci3-round4-frozen-home';
    const paths = subject.deriveFrozenControllerPublisherPaths(context, '9'.repeat(64));
    const requestRoot = path.join('/private/ci3-round4-frozen-home', '.config', 'agentempp', 'ci3', 'publisher-input', context.authority.commit);
    assert.deepEqual(paths, {
      request_root: requestRoot,
      request_path: path.join(requestRoot, 'publisher1-transaction.request.json'),
      receiver_root: path.join(requestRoot, 'receiver', context.generations.remote, context.generations.controller, '9'.repeat(64)),
    });
  } finally {
    if (originalHome === undefined) delete process.env.HOME; else process.env.HOME = originalHome;
  }
});

test('round3 actual main performs the parent-pinned local prepare and materializes no caller-selected path', async () => {
  const fixture = await createActualCliFixture('prepare');
  try {
    const result = runActualCli(fixture.root, '--prepare');
    assert.equal(result.status, 0, result.stderr);
    for (const role of subject.PREPARE_CANDIDATE_ROLES) {
      const candidate = await lstat(path.join(fixture.authorityRoot, 'candidates', `${role}.candidate`));
      assert.equal(candidate.isFile(), true);
      assert.equal(candidate.mode & 0o777, 0o600);
    }
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

for (const mode of ['--provision-vps-publisher0', '--receive-vps-pass', '--verify-chain']) {
  test(`round3 actual main executes exactly one closed fixed ${mode} adapter and recovers exact-existing`, async () => {
    const fixture = await createActualCliFixture(mode.slice(2));
    try {
      if (mode === '--provision-vps-publisher0') assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
      if (mode === '--receive-vps-pass' || mode === '--verify-chain') {
        assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
        assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
      }
      if (mode === '--verify-chain') {
        assert.equal(runActualCli(fixture.root, '--receive-vps-pass').status, 0);
        assert.equal(runActualCli(fixture.root, '--provision-mac-publisher1').status, 0);
      }
      const first = runActualCli(fixture.root, mode);
      assert.equal(first.status, 0, first.stderr);
      const operation = mode.slice(2);
      const marker = path.join(fixture.root, 'fixed-bin', `${operation}.ran`);
      assert.equal((await lstat(marker)).isFile(), true);
      const state = path.join(fixture.authorityRoot, 'state', operation);
      assert.equal((await lstat(path.join(state, 'attempt.json'))).isFile(), true);
      assert.equal((await lstat(path.join(state, 'result.json'))).isFile(), true);
      const second = runActualCli(fixture.root, mode);
      assert.equal(second.status, 0, second.stderr);
    } finally { await cleanupSyntheticFixture(fixture.root); }
  });
}

test('round3 receive and verify use the reviewed chain executable with ambient Mac helpers absent', async () => {
  const fixture = await createActualCliFixture('authority-builtins-no-ambient-helpers');
  try {
    const prepared = runActualCli(fixture.root, '--prepare');
    assert.equal(prepared.status, 0, prepared.stderr);
    const publisher0 = runActualCli(fixture.root, '--provision-vps-publisher0');
    assert.equal(
      publisher0.status,
      0,
      `${publisher0.stderr}${JSON.stringify(await publisher0LifecycleDiagnostic(fixture.sourceRoot))}`,
    );
    const receiveAdapter = path.join(fixture.root, 'fixed-bin', 'receive-vps-pass');
    await rm(receiveAdapter);
    const received = runActualCli(fixture.root, '--receive-vps-pass');
    assert.equal(received.status, 0, received.stderr);
    await assert.rejects(lstat(path.join(fixture.root, 'fixed-bin', 'receive-vps-pass.ran')), { code: 'ENOENT' });
    assert.equal(runActualCli(fixture.root, '--provision-mac-publisher1').status, 0);
    const verifyAdapter = path.join(fixture.root, 'fixed-bin', 'verify-chain');
    await rm(verifyAdapter);
    const verified = runActualCli(fixture.root, '--verify-chain');
    assert.equal(verified.status, 0, verified.stderr);
    await assert.rejects(lstat(path.join(fixture.root, 'fixed-bin', 'verify-chain.ran')), { code: 'ENOENT' });
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round3 actual outer ledger recovers every settled operation after generic result loss without a second adapter effect', async () => {
  const fixture = await createActualCliFixture('outer-ledger-settled-recovery');
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    for (const mode of [
      '--provision-vps-publisher0', '--receive-vps-pass', '--provision-mac-publisher1', '--verify-chain',
    ]) {
      const created = runActualCli(fixture.root, mode);
      assert.equal(created.status, 0, `${mode}: ${created.stderr}`);
      const operation = mode.slice(2);
      const stateRoot = path.join(fixture.authorityRoot, 'state', operation);
      await rm(path.join(stateRoot, 'result.json'));
      const recovered = runActualCli(fixture.root, mode);
      assert.equal(recovered.status, 0, `${mode}: ${recovered.stderr}`);
      assert.equal((await lstat(path.join(stateRoot, 'result.json'))).isFile(), true);
      assert.equal((await lstat(path.join(stateRoot, 'attempt.json'))).isFile(), true);
      assert.equal(fixture.context.authority.commit.length, 40);
    }
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round3 verify recovery rejects Phase B settlement without its own controller claim tree result and settlement', async () => {
  const fixture = await createActualCliFixture('verify-operation-specific-recovery');
  try {
    for (const mode of [
      '--prepare', '--provision-vps-publisher0', '--receive-vps-pass',
      '--provision-mac-publisher1',
    ]) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    const stateRoot = path.join(fixture.authorityRoot, 'state', 'verify-chain');
    await writeOwnerOnlyFixture(path.join(stateRoot, 'attempt.json'), subject.canonicalJson({
      schema_version: 1, purpose: 'CI3_EXTERNAL_PUBLISHER_ATTEMPT_V1',
      authority_sha: fixture.context.authority.commit,
      controller_generation_id: fixture.context.generations.controller,
      operation: 'verify-chain', attempt: 1, retry: false, raw_values: false,
    }));
    const recovery = runActualCli(fixture.root, '--verify-chain');
    assert.equal(recovery.status, 1);
    assert.equal(recovery.stderr, 'STOP_PRE_AUTHORITY mode=--verify-chain raw_values=false\n');
    await assert.rejects(lstat(path.join(stateRoot, 'result.json')), { code: 'ENOENT' });
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round3 Phase B installs the complete canonical launcher root and only then produces its operation publisher request', async () => {
  const fixture = await createActualCliFixture('phase-b-launcher-and-request');
  try {
    const publisherInputRoot = path.join(
      fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit,
    );
    const operationRequestPath = path.join(publisherInputRoot, 'operation-authority.publisher-request.json');
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
    assert.equal(runActualCli(fixture.root, '--receive-vps-pass').status, 0);
    await assert.rejects(lstat(operationRequestPath), { code: 'ENOENT' });
    const phaseB = runActualCli(fixture.root, '--provision-mac-publisher1');
    assert.equal(phaseB.status, 0, phaseB.stderr);
    const installedRoot = path.join(
      fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
      `bootstrap-${fixture.context.authority.manifest_sha256}`,
    );
    for (const [relative, mode] of [
      ['publisher1-materializer.authority.json', 0o444],
      ['vps-issuer-authority.receipt.json', 0o444],
      ['runtime/ci3-terminal-anchor-writer', 0o555],
      ['runtime/node', 0o555],
      ['runtime/ci3-bridge-controller.mjs', 0o555],
      ['runtime/ci3-bridge-launcher.zsh', 0o555],
      ['runtime/launcher-bootstrap.authority.v1', 0o444],
      ['runtime/launch-attestation.json', 0o444],
      ['runtime/authority-manifest.v1', 0o444],
    ]) {
      const observed = await lstat(path.join(installedRoot, relative));
      assert.equal(observed.isFile(), true, relative);
      assert.equal(observed.mode & 0o777, mode, relative);
    }
    const requestBytes = await readFile(operationRequestPath);
    const request = JSON.parse(requestBytes.toString('utf8'));
    assert.equal(request.purpose, 'CI3_OPERATION_AUTHORITY_PUBLISHER_REQUEST_V1');
    assert.equal(request.authority_sha, fixture.context.authority.commit);
    assert.equal(request.vps_issuer_authority_path, path.join(
      '/Library/Application Support/Agentempp/ci3-publisher1-bootstrap', fixture.context.authority.commit,
      `bootstrap-${fixture.context.authority.manifest_sha256}`, 'vps-issuer-authority.receipt.json',
    ));
    assert.equal(requestBytes.equals(subject.canonicalJson(request)), true);
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round3 causal request feeds the real operation consumer through sixteen targets, six scans, settlement and later writer reachability', async () => {
  const fixture = await createActualCliFixture('causal-real-consumer-tail');
  let settled = null;
  let adminInvocations = 0;
  let settlementPersisted = false;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass', '--provision-mac-publisher1']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    const bootstrapRoot = path.join(
      fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
      `bootstrap-${fixture.context.authority.manifest_sha256}`,
    );
    const issuerBytes = await readFile(path.join(bootstrapRoot, 'vps-issuer-authority.receipt.json'));
    const materializer = JSON.parse((await readFile(
      path.join(bootstrapRoot, 'publisher1-materializer.authority.json'),
    )).toString('utf8'));
    const writerBytes = await readFile(path.join(bootstrapRoot, 'runtime', 'ci3-terminal-anchor-writer'));
    const launchAttestation = JSON.parse(fixture.publisherOutputs.bytesByRole['launch-attestation'].toString('utf8'));
    const publisher = await controllerContract.createOperationAuthorityPublisher({
      launchAttestation,
      io: {
        homeDirectory: fixture.root,
        readRootImmutableFile: async (filePath, expectedSha256, expectedMode, code) => {
          assert.equal(filePath, path.join(
            '/Library/Application Support/Agentempp/ci3-publisher1-bootstrap', fixture.context.authority.commit,
            `bootstrap-${fixture.context.authority.manifest_sha256}`, 'vps-issuer-authority.receipt.json',
          ));
          assert.equal(expectedSha256, subject.sha256(issuerBytes));
          assert.equal(expectedMode, 0o444);
          assert.equal(code, 'STOP_PRE_AUTHORITY');
          return { bytes: issuerBytes, metadata: { uid: 0, gid: 0, mode: 0o444, nlink: 1 }, immutable: true };
        },
        readPublisher1MaterializerAuthority: async (context, binding) => {
          assert.equal(context.authority.commit, fixture.context.authority.commit);
          assert.equal(context.authority.manifest_sha256, fixture.context.authority.manifest_sha256);
          assert.deepEqual(context.authority.components, fixture.context.authority.components);
          assert.deepEqual(context.generations, fixture.context.generations);
          assert.equal(binding.receiverLeaves.length, 16);
          return {
            authority: materializer,
            authorityPath: path.join(bootstrapRoot, 'publisher1-materializer.authority.json'),
            binaryPath: materializer.materializer_path,
            binary: { bytes: writerBytes, metadata: { uid: 0, gid: 0, mode: 0o555, nlink: 1 }, immutable: true },
          };
        },
        observePublisher1: async ({ expected, expectedShaByRole, bytesByRole, installation, publisher1Request }) => {
          assert.equal(Object.keys(expectedShaByRole).length, 16);
          assert.equal(Object.keys(bytesByRole).length, 16);
          assert.equal(Object.keys(installation.targets).length, 16);
          assert.equal(publisher1Request.entries.length, 16);
          return settled ?? { state: 'ABSENT' };
        },
        invokeAdmin: async ({ expected, expectedShaByRole }) => {
          adminInvocations += 1;
          assert.equal(Object.keys(expectedShaByRole).length, 16);
          settled = {
            state: 'SETTLED', ...expected, claim_sha256: '1'.repeat(64), result_sha256: '2'.repeat(64),
            tree_verified: true, raw_values: false,
          };
        },
        persistReceipt: async ({ settled: observation, expectedShaByRole }) => {
          assert.deepEqual(observation, settled);
          assert.equal(Object.keys(expectedShaByRole).length, 16);
          settlementPersisted = true;
        },
      },
    });
    assert.deepEqual(await publisher.publishOperationAuthority(), { status: 'CREATED', raw_values: false });
    assert.equal(adminInvocations, 1);
    assert.equal(settlementPersisted, true);
    assert.equal(controllerContract.TERMINAL_SCAN_IDS.length, 6);
    const later = await controllerContract.dispatchControllerMode({
      mode: 'publish-privileged-writer-authority',
      adapters: { publishPrivilegedWriterAuthority: async () => ({ status: 'CREATED', raw_values: false }) },
    });
    assert.deepEqual(later, {
      mode: 'publish-privileged-writer-authority', state: 'PRIVILEGED_WRITER_AUTHORITY_PUBLISHED', raw_values: false,
    });
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round4 installed launcher self-test crosses zsh and the real controller consumer with causal request sixteen targets scans and denied terminal', async () => {
  const fixture = await createActualCliFixture('round4-installed-launcher-consumer', { frozenWriter: true });
  try {
    const requestRoot = path.join(
      fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit,
    );
    const operationRequestPath = path.join(requestRoot, 'operation-authority.publisher-request.json');
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    await assert.rejects(lstat(operationRequestPath));
    const publisher1 = runActualCli(fixture.root, '--provision-mac-publisher1');
    assert.equal(publisher1.status, 0, publisher1.stderr);
    const operationRequestBytes = await readFile(operationRequestPath);
    const installedRoot = path.join(
      fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
      `bootstrap-${fixture.context.authority.manifest_sha256}`,
    );
    const installedLauncher = path.join(installedRoot, 'runtime', 'ci3-bridge-launcher.zsh');
    const receiptPath = path.join(fixture.root, 'round4-installed-operation-e2e.receipt.json');
    await assert.rejects(lstat(path.join(
      fixture.sourceRoot, 'publisher1-produced', 'round4-installed-operation-e2e.request.json',
    )));
    const targetRoot = path.join(
      fixture.root, 'publisher1-terminal-authority', fixture.context.authority.commit,
    );
    await assert.rejects(lstat(targetRoot));
    const launcherEnvironment = {
      PATH: '/usr/bin:/bin', CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT: installedRoot,
      CI3_SYNTHETIC_EXTERNAL_AUTHORITY_SHA: fixture.context.authority.commit,
    };
    assert.equal(typeof controllerContract.publishPrivilegedWriterAuthority, 'function');
    const launched = spawnSync('/bin/zsh', [installedLauncher, '--self-test'], {
      encoding: 'utf8', env: launcherEnvironment, timeout: 30_000, maxBuffer: 1024 * 1024,
    });
    assert.equal(launched.status, 0, launched.stderr);
    assert.match(launched.stdout, /^LAUNCHER_EXTERNAL_SELF_TEST PASS/);
    const receiptBytes = await readFile(receiptPath);
    const receipt = JSON.parse(receiptBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(receipt), receiptBytes);
    assert.equal(receipt.operation_request_sha256, subject.sha256(operationRequestBytes));
    assert.equal(receipt.target_count, 16);
    assert.equal(receipt.target_observations.length, 16);
    assert.deepEqual(
      receipt.target_observations.map(({ role }) => role).sort(),
      [...subject.PUBLISHER1_ROLES].sort(),
    );
    assert.deepEqual(receipt.scan_results.map(({ id }) => id), controllerContract.TERMINAL_SCAN_IDS);
    assert.equal(receipt.scan_results.every(({ match_count }) => match_count === 0), true);
    assert.equal(receipt.operational_collectors, true);
    assert.equal(receipt.collector_implementation, 'collectActualTerminalSurfaces');
    for (const scan of receipt.scan_results) {
      const surfacePath = path.join(requestRoot, 'round4-scan-surfaces', `${scan.id}.surface`);
      const surfaceBytes = await readFile(surfacePath);
      const surface = JSON.parse(surfaceBytes.toString('utf8'));
      assert.deepEqual(subject.canonicalJson(surface), surfaceBytes);
      assert.equal(surface.purpose, 'CI3_FINAL_OPERATION_SCAN_SURFACE_V1');
      assert.equal(surface.scan_id, scan.id);
      assert.equal(surface.source_observation.purpose, 'CI3_TERMINAL_SCAN_SOURCE_OBSERVATION_V1');
      assert.equal(surface.source_observation.scan_id, scan.id);
      assert.equal(scan.surface_sha256, subject.sha256(surfaceBytes));
      assert.equal(scan.surface_byte_length, surfaceBytes.length);
      assert.equal(scan.surface_role, controllerContract.SCAN_SURFACE_CONTRACTS[scan.id].source_role);
      assert.equal(surfaceBytes.length > 0, true);
    }
    assert.equal(receipt.scan_surface_set_sha256, subject.sha256(subject.canonicalJson(
      receipt.scan_results.map(({ id, surface_sha256: surfaceSha256 }) => ({ id, surface_sha256: surfaceSha256 })),
    )));
    assert.equal(receipt.later_writer_sha256, subject.sha256(await readFile(path.join(
      installedRoot, 'runtime', 'ci3-terminal-anchor-writer',
    ))));
    const laterDispatchBytes = await readFile(path.join(requestRoot, 'later-writer.no-effect.dispatch.json'));
    const laterDispatch = JSON.parse(laterDispatchBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(laterDispatch), laterDispatchBytes);
    assert.equal(receipt.later_writer_dispatch_receipt_sha256, subject.sha256(laterDispatchBytes));
    assert.deepEqual(laterDispatch, {
      schema_version: 1,
      purpose: 'CI3_SYNTHETIC_LATER_WRITER_NO_EFFECT_DISPATCH_V1',
      authority_sha: fixture.context.authority.commit,
      controller_generation_id: fixture.context.generations.controller,
      operation_request_sha256: subject.sha256(operationRequestBytes),
      publisher1_settlement_sha256: receipt.settlement_sha256,
      writer_sha256: receipt.later_writer_sha256,
      target_count: 16,
      dispatch_mode: 'publish-privileged-writer-authority',
      dispatch_state: 'PRIVILEGED_WRITER_AUTHORITY_PUBLISHED',
      consumer_implementation: 'publishPrivilegedWriterAuthority',
      effect_seam_position: 'BELOW_CONSUMER',
      effect_executions: 0,
      privilege_prompts: 0,
      raw_values: false,
    });
    assert.equal(receipt.later_writer_reachable, true);
    assert.equal(receipt.terminal_privilege_invocations, 0);
    await lstat(targetRoot);
    await lstat(path.join(requestRoot, 'publisher1-controller.settlement.json'));

    const terminalDenied = spawnSync('/bin/zsh', [installedLauncher, 'publish-privileged-writer-authority'], {
      encoding: 'utf8', env: launcherEnvironment, timeout: 30_000, maxBuffer: 1024 * 1024,
    });
    assert.notEqual(terminalDenied.status, 0);
    assert.match(terminalDenied.stderr, /^ERROR STOP_PRE_AUTHORITY\n$/);
  } finally {
    await cleanupSyntheticFixture(fixture.root);
  }
});

test('round5 actual Publisher0-to-Publisher1 compiles the authority-bound installer and installs the automatic canonical transaction', async () => {
  const fixture = await createActualCliFixture('sequence');
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    const publisher0 = runActualCli(fixture.root, '--provision-vps-publisher0');
    assert.equal(publisher0.status, 0, publisher0.stderr);
    const transported = runActualCli(fixture.root, '--receive-vps-pass');
    assert.equal(transported.status, 0, transported.stderr);
    const receiverManifestSha256 = fixture.receiverManifestSha256;
    const requestRoot = path.join(fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit);
    const receiverRoot = path.join(requestRoot, 'receiver', fixture.context.generations.remote, fixture.context.generations.controller, receiverManifestSha256);
    const requestPath = path.join(requestRoot, 'publisher1-transaction.request.json');
    const before = await lstat(requestPath, { bigint: true });
    const leafBefore = await Promise.all(subject.PUBLISHER1_ROLES.map((role) => lstat(path.join(receiverRoot, `${role}.payload`), { bigint: true })));
    const installRequest = path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-bootstrap.request.json');
    assert.equal((await lstat(installRequest)).isFile(), true);
    const publisher1 = runActualCli(fixture.root, '--provision-mac-publisher1');
    assert.equal(publisher1.status, 0, publisher1.stderr);
    await assert.rejects(lstat(path.join(fixture.root, 'fixed-bin', 'provision-mac-publisher1.ran')));
    const installedRoot = path.join(fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
      `bootstrap-${fixture.context.authority.manifest_sha256}`);
    const installedMaterializer = await lstat(path.join(installedRoot, 'publisher1-materializer.authority.json'));
    assert.equal(installedMaterializer.isFile(), true);
    assert.equal(installedMaterializer.mode & 0o777, 0o444);
    assert.equal((await lstat(path.join(installedRoot, 'runtime', 'ci3-terminal-anchor-writer'))).mode & 0o777, 0o555);
    assert.equal((await lstat(path.join(fixture.root, 'publisher1-state-base', fixture.context.authority.commit,
      fixture.context.generations.controller, 'publisher1-bootstrap.result.json'))).mode & 0o777, 0o444);
    const compilerReceipt = await lstat(path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-installer.compile-receipt.json'));
    assert.equal(compilerReceipt.mode & 0o777, 0o600);
    assert.equal((await lstat(path.join(fixture.sourceRoot, 'publisher1-produced', 'runtime',
      'ci3-publisher1-bootstrap-installer'))).mode & 0o777, 0o700);
    const after = await lstat(requestPath, { bigint: true });
    const leafAfter = await Promise.all(subject.PUBLISHER1_ROLES.map((role) => lstat(path.join(receiverRoot, `${role}.payload`), { bigint: true })));
    assert.equal(before.dev, after.dev);
    assert.equal(before.ino, after.ino);
    for (const [index, leaf] of leafBefore.entries()) {
      assert.equal(leaf.dev, leafAfter[index].dev);
      assert.equal(leaf.ino, leafAfter[index].ino);
    }
    const exactExisting = runActualCli(fixture.root, '--provision-mac-publisher1');
    assert.equal(exactExisting.status, 0, exactExisting.stderr);
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('successor actual main starts without Publisher0 outputs and crosses receiver request human preflight and immutable installer in order', async () => {
  const fixture = await createActualCliFixture('successor-no-preseed');
  try {
    for (const relativePath of [
      'publisher1-input/issuer.json', 'publisher1-input/pass.json', 'publisher1-input/transport.json',
      'publisher1-input/human.json', 'pre-materialization/receiver-manifest.sha256',
      ...subject.PUBLISHER1_ROLES.map((role) => `pre-materialization/${role}.payload`),
    ]) await assert.rejects(lstat(path.join(fixture.sourceRoot, relativePath)));
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
    await assert.rejects(lstat(path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-bootstrap.request.json')));
    const receive = runActualCli(fixture.root, '--receive-vps-pass');
    if (receive.status !== 0) {
      const diagnostic = {};
      for (const [name, file] of Object.entries({
        operational: path.join(fixture.sourceRoot, 'publisher1-produced', 'runtime', 'ci3-terminal-anchor-writer'),
        validation: path.join(fixture.sourceRoot, 'publisher1-produced', 'runtime', 'ci3-publisher1-semantic-preflight'),
        compileReceipt: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-writer.compile-receipt.json'),
        bootstrap: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-bootstrap.request.json'),
        descriptor: path.join(fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit,
          'publisher1-transaction.request.json'),
        receiverLeaf: path.join(fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit,
          'receiver', fixture.context.generations.remote, fixture.context.generations.controller,
          fixture.receiverManifestSha256, 'node-runtime.payload'),
        humanOutput: path.join(fixture.sourceRoot, 'receiver-output', 'human-authorization.payload'),
      })) diagnostic[name] = await lstat(file).then(() => true, () => false);
      assert.equal(receive.status, 0, `${receive.stderr}${JSON.stringify(diagnostic)}`);
    }
    assert.equal((await lstat(path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-bootstrap.request.json'))).mode & 0o777, 0o600);
    await assert.rejects(lstat(path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-semantic-preflight.receipt.json')));
    await assert.rejects(lstat(path.join(fixture.root, 'publisher1-installer-base', fixture.context.authority.commit,
      fixture.context.generations.controller)));
    const publisher1 = runActualCli(fixture.root, '--provision-mac-publisher1');
    if (publisher1.status !== 0) {
      const diagnostic = {};
      for (const [name, file] of Object.entries({
        preflightRequest: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-semantic-preflight.request.json'),
        preflightReceipt: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-semantic-preflight.receipt.json'),
        installerBinary: path.join(fixture.sourceRoot, 'publisher1-produced', 'runtime', 'ci3-publisher1-bootstrap-installer'),
        immutableRequest: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-immutable-installer.request.json'),
      })) diagnostic[name] = await lstat(file).then(() => true, () => false);
      if (diagnostic.preflightRequest) {
        const validationPath = path.join(fixture.sourceRoot, 'publisher1-produced', 'runtime', 'ci3-publisher1-semantic-preflight');
        const requestBytes = await readFile(path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-semantic-preflight.request.json'));
        const validation = spawnSync(validationPath, [
          '--publisher1-semantic-preflight',
          path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-semantic-preflight.request.json'),
          subject.sha256(requestBytes),
        ], { encoding: 'utf8', env: subject.CLOSED_ENVIRONMENT, timeout: 30_000, maxBuffer: 16 * 1024 });
        diagnostic.validationStatus = validation.status;
        diagnostic.validationFailureClass = /^ERROR ([A-Z0-9_]+)/.exec(validation.stderr)?.[1] ?? 'NONE';
      }
      assert.equal(publisher1.status, 0, `${publisher1.stderr}${JSON.stringify(diagnostic)}`);
    }
    const receiptPath = path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-semantic-preflight.receipt.json');
    const receiptBytes = await readFile(receiptPath);
    const receipt = JSON.parse(receiptBytes.toString('utf8'));
    const validationBinary = path.join(fixture.sourceRoot, 'publisher1-produced', 'runtime', 'ci3-publisher1-semantic-preflight');
    assert.equal(receipt.validation_binary_sha256, subject.sha256(await readFile(validationBinary)));
    assert.equal(receipt.writes_performed, 0);
    assert.equal(receipt.effect_executions, 0);
    assert.equal(receipt.network_calls, 0);
    assert.equal(receipt.privilege_prompts, 0);
    assert.equal((await lstat(receiptPath)).mode & 0o777, 0o600);
    assert.equal((await lstat(path.join(fixture.root, 'publisher1-installer-base', fixture.context.authority.commit,
      fixture.context.generations.controller, 'runtime', 'ci3-publisher1-bootstrap-installer'))).mode & 0o777, 0o555);
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('successor actual P0 captures the authenticated stdout protocol without local output preseed or future candidates', async () => {
  const fixture = await createActualCliFixture('successor-authenticated-p0-capture');
  try {
    const capturePath = path.join(fixture.sourceRoot, 'publisher0-output.capture.json');
    await assert.rejects(lstat(capturePath));
    await assert.rejects(lstat(fixture.fakeRemoteRoot));
    for (const role of subject.PUBLISHER1_ROLES.filter((value) => value !== 'ssh-config')) {
      await assert.rejects(lstat(path.join(fixture.sourceRoot, 'candidates', `${role}.payload`)));
    }
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    const publisher0 = runActualCli(fixture.root, '--provision-vps-publisher0');
    if (publisher0.status !== 0) {
      const diagnostic = {};
      for (const [name, file] of Object.entries({
        attempt: path.join(fixture.authorityRoot, 'state', 'provision-vps-publisher0', 'attempt.json'),
        request: path.join(fixture.sourceRoot, 'publisher0-transport', 'session.request.json'),
        started: path.join(fixture.sourceRoot, 'publisher0-transport', 'started.json'),
        quiesced: path.join(fixture.sourceRoot, 'publisher0-transport', 'quiesced.json'),
        journal: path.join(fixture.sourceRoot, 'publisher0-output.capture.journal'),
        ack: path.join(fixture.sourceRoot, 'publisher0-transport', 'local-ack.json'),
        journalPrefix: path.join(fixture.sourceRoot, 'publisher0-transport', 'journal-prefix-synced.json'),
        journalComplete: path.join(fixture.sourceRoot, 'publisher0-transport', 'journal-complete.json'),
        ackObserved: path.join(fixture.sourceRoot, 'publisher0-transport', 'ack-observed.json'),
        ackSent: path.join(fixture.sourceRoot, 'publisher0-transport', 'ack-sent.json'),
        ackFlushed: path.join(fixture.sourceRoot, 'publisher0-transport', 'ack-flushed.json'),
        remotePrepared: path.join(fixture.sourceRoot, 'publisher0-transport', 'remote-prepared.json'),
        remoteAckAccepted: path.join(fixture.sourceRoot, 'publisher0-transport', 'remote-ack-accepted.json'),
        remoteClosed: path.join(fixture.sourceRoot, 'publisher0-transport', 'remote-closed.json'),
        failed: path.join(fixture.sourceRoot, 'publisher0-transport', 'failed.json'),
        completed: path.join(fixture.sourceRoot, 'publisher0-transport', 'completed.json'),
      })) diagnostic[name] = await lstat(file).then((value) => Number(value.size), () => -1);
      diagnostic.journalCanonical = false;
      diagnostic.journalAuthenticated = false;
      try {
        const diagnosticJournal = await readFile(path.join(fixture.sourceRoot, 'publisher0-output.capture.journal'));
        const diagnosticOutput = JSON.parse(diagnosticJournal.toString('utf8'));
        diagnostic.journalCanonical = subject.canonicalJson(diagnosticOutput).equals(diagnosticJournal);
        diagnostic.journalAuthenticated = subject.validateAuthenticatedPublisher0Output(diagnosticOutput, fixture.context).raw_values === false;
      } catch {}
      try {
        const quiesced = JSON.parse((await readFile(path.join(
          fixture.sourceRoot, 'publisher0-transport', 'quiesced.json',
        ))).toString('utf8'));
        diagnostic.brokerState = quiesced.state;
        diagnostic.pendingFilesystemWrites = quiesced.pending_filesystem_writes;
      } catch {}
      try {
        const failed = JSON.parse((await readFile(path.join(
          fixture.sourceRoot, 'publisher0-transport', 'failed.json',
        ))).toString('utf8'));
        diagnostic.failureStage = failed.failure_stage;
      } catch {}
      diagnostic.startedBinding = false;
      try {
        const requestBytes = await readFile(path.join(fixture.sourceRoot, 'publisher0-transport', 'session.request.json'));
        const request = JSON.parse(requestBytes.toString('utf8'));
        const startedBytes = await readFile(path.join(fixture.sourceRoot, 'publisher0-transport', 'started.json'));
        const started = JSON.parse(startedBytes.toString('utf8'));
        diagnostic.startedBinding = started.broker_request_sha256 === subject.sha256(requestBytes)
          && started.authority_sha === request.authority_sha
          && started.controller_generation_id === request.controller_generation_id
          && started.script_sha256 === request.script_sha256
          && started.executable_sha256 === request.executable_sha256;
      } catch {}
      try {
        const remoteClosed = JSON.parse((await readFile(path.join(
          fixture.sourceRoot, 'publisher0-transport', 'remote-closed.json',
        ))).toString('utf8'));
        diagnostic.remoteStatus = remoteClosed.remote_status;
        diagnostic.remoteSignal = remoteClosed.remote_signal;
        diagnostic.remoteFailureClass = remoteClosed.remote_failure_class;
      } catch {}
      assert.equal(publisher0.status, 0, `${publisher0.stderr}${JSON.stringify(diagnostic)}`);
    }
    assert.equal((await lstat(capturePath)).mode & 0o777, 0o600);
    const captureBytes = await readFile(capturePath);
    assert.deepEqual(subject.canonicalJson(JSON.parse(captureBytes.toString('utf8'))), captureBytes);
    assert.equal(subject.validateAuthenticatedPublisher0Output(JSON.parse(captureBytes.toString('utf8')), fixture.context).raw_values, false);
    const brokerRequestBytes = await readFile(path.join(
      fixture.sourceRoot, 'publisher0-transport', 'session.request.json',
    ));
    const brokerQuiescedBytes = await readFile(path.join(
      fixture.sourceRoot, 'publisher0-transport', 'quiesced.json',
    ));
    assert.deepEqual(brokerQuiescedBytes, subject.canonicalJson({
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_QUIESCED_V1',
      authority_sha: fixture.context.authority.commit,
      controller_generation_id: fixture.context.generations.controller,
      broker_request_sha256: subject.sha256(brokerRequestBytes),
      state: 'QUIESCED',
      pending_filesystem_writes: 0,
      attempt: 1,
      retry: false,
      raw_values: false,
    }));
    const transportEntries = await readdir(path.join(fixture.sourceRoot, 'publisher0-transport'));
    assert.deepEqual(transportEntries.filter((entry) => entry.endsWith('.publishing')), []);
    for (const receiptName of [
      'started', 'journal-complete', 'ack-observed', 'ack-sent', 'ack-flushed',
      'remote-closed', 'completed', 'quiesced',
    ]) {
      const receiptPath = path.join(fixture.sourceRoot, 'publisher0-transport', `${receiptName}.json`);
      const receiptStat = await lstat(receiptPath);
      const receiptBytes = await readFile(receiptPath);
      assert.equal(receiptStat.mode & 0o777, 0o600);
      assert.equal(receiptStat.nlink, 1);
      assert.deepEqual(receiptBytes, subject.canonicalJson(JSON.parse(receiptBytes.toString('utf8'))));
    }
    const transactionRoot = path.join(
      fixture.fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority', fixture.context.authority.commit,
      fixture.publisher0TransactionGenerationId,
    );
    assert.equal((await lstat(path.join(transactionRoot, 'issuer-signing-key.pkcs8'))).mode & 0o777, 0o400);
    assert.equal((await readdir(path.join(transactionRoot, 'publisher-input'))).length, 11);
    assert.equal((await lstat(path.join(fixture.root, 'fixed-bin', 'provision-vps-publisher0.ran'))).mode & 0o777, 0o600);
    for (const legacy of ['issuer.json', 'pass.json', 'transport.json']) {
      await assert.rejects(lstat(path.join(fixture.sourceRoot, 'publisher0-output', legacy)));
    }
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round4 actual outer P0 entrypoint recovers a settled remote from its durable local journal without a second SSH', async () => {
  const fixture = await createActualCliFixture('round4-p0-journal-recovery');
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    const crashed = runActualCli(fixture.root, '--provision-vps-publisher0', {
      CI3_SYNTHETIC_PUBLISHER0_CRASH_AFTER_JOURNAL: '1',
    });
    assert.equal(crashed.status, 1);
    assert.match(
      crashed.stderr,
      /^SYNTHETIC_CRASH\n$/,
      JSON.stringify(await publisher0LifecycleDiagnostic(fixture.sourceRoot)),
    );
    const stateRoot = path.join(fixture.authorityRoot, 'state', 'provision-vps-publisher0');
    const capturePath = path.join(fixture.sourceRoot, 'publisher0-output.capture.json');
    const journalPath = path.join(fixture.sourceRoot, 'publisher0-output.capture.journal');
    await lstat(path.join(stateRoot, 'attempt.json'));
    await assert.rejects(lstat(path.join(stateRoot, 'result.json')));
    await assert.rejects(lstat(capturePath));
    const journalBytes = await readFile(journalPath);
    assert.deepEqual(subject.canonicalJson(JSON.parse(journalBytes.toString('utf8'))), journalBytes);
    const markerPath = path.join(fixture.root, 'fixed-bin', 'provision-vps-publisher0.ran');
    const markerBefore = await lstat(markerPath, { bigint: true });

    const recovered = runActualCli(fixture.root, '--provision-vps-publisher0');
    assert.equal(recovered.status, 0, recovered.stderr);
    const markerAfter = await lstat(markerPath, { bigint: true });
    assert.equal(markerAfter.dev, markerBefore.dev);
    assert.equal(markerAfter.ino, markerBefore.ino);
    assert.deepEqual(await readFile(capturePath), journalBytes);
    await lstat(path.join(stateRoot, 'result.json'));
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round5 actual P0 durable decision survives all remote PREPARED to local ACK kill windows without a second SSH', async () => {
  const stages = [
    'remote-prepared-before-first-local-chunk',
    'before-last-local-chunk',
    'after-local-ack',
  ];
  for (const stage of stages) {
    const fixture = await createActualCliFixture(`round5-p0-distributed-${stage}`);
    const transportRoot = path.join(fixture.sourceRoot, 'publisher0-transport');
    const barrierPath = path.join(transportRoot, `${stage}.prepared.json`);
    const stateRoot = path.join(fixture.authorityRoot, 'state', 'provision-vps-publisher0');
    const journalPath = path.join(fixture.sourceRoot, 'publisher0-output.capture.journal');
    const capturePath = path.join(fixture.sourceRoot, 'publisher0-output.capture.json');
    const ackPath = path.join(transportRoot, 'local-ack.json');
    const completedPath = path.join(transportRoot, 'completed.json');
    const transactionRoot = path.join(
      fixture.fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority', fixture.context.authority.commit,
      fixture.publisher0TransactionGenerationId,
    );
    const remoteOutputPath = path.join(transactionRoot, 'authenticated-publisher0-output.json');
    let original = null;
    let recovery = null;
    try {
      assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
      original = spawnActualCli(fixture.root, '--provision-vps-publisher0', {
        CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER: stage,
      });
      const originalResult = collectActualCli(original);
      await waitForFixturePath(barrierPath, original);
      await lstat(path.join(stateRoot, 'attempt.json'));
      await assert.rejects(lstat(path.join(stateRoot, 'result.json')), { code: 'ENOENT' });
      await assert.rejects(lstat(remoteOutputPath), { code: 'ENOENT' });
      await lstat(path.join(transactionRoot, 'authenticated-publisher0-output.prepared.json'));
      const markerPath = path.join(fixture.root, 'fixed-bin', 'provision-vps-publisher0.ran');
      const markerBefore = await lstat(markerPath, { bigint: true });
      const journalBytesBefore = await readFile(journalPath);
      if (stage === 'remote-prepared-before-first-local-chunk') {
        assert.equal(journalBytesBefore.length, 0);
        await assert.rejects(lstat(ackPath), { code: 'ENOENT' });
      } else if (stage === 'before-last-local-chunk') {
        assert.ok(journalBytesBefore.length > 0);
        const partialOutput = JSON.parse(journalBytesBefore.toString('utf8'));
        const completeCanonicalBytes = subject.canonicalJson(partialOutput);
        assert.equal(completeCanonicalBytes.length, journalBytesBefore.length + 1);
        assert.deepEqual(completeCanonicalBytes.subarray(0, journalBytesBefore.length), journalBytesBefore);
        assert.notDeepEqual(completeCanonicalBytes, journalBytesBefore);
        await assert.rejects(lstat(ackPath), { code: 'ENOENT' });
      } else {
        assert.deepEqual(subject.canonicalJson(JSON.parse(journalBytesBefore.toString('utf8'))), journalBytesBefore);
        const ackBytes = await readFile(ackPath);
        assert.deepEqual(subject.canonicalJson(JSON.parse(ackBytes.toString('utf8'))), ackBytes);
      }

      original.kill('SIGKILL');
      const crashed = await originalResult;
      assert.equal(crashed.signal, 'SIGKILL');
      await releasePublisher0TransportBarrier(fixture.sourceRoot, stage);
      recovery = spawnActualCli(fixture.root, '--provision-vps-publisher0');
      const recovered = await collectActualCli(recovery);
      assert.equal(recovered.status, 0, `${stage}: ${recovered.stderr}`);
      const markerAfter = await lstat(markerPath, { bigint: true });
      assert.equal(markerAfter.dev, markerBefore.dev);
      assert.equal(markerAfter.ino, markerBefore.ino);
      const journalBytes = await readFile(journalPath);
      assert.deepEqual(subject.canonicalJson(JSON.parse(journalBytes.toString('utf8'))), journalBytes);
      assert.deepEqual(await readFile(capturePath), journalBytes);
      const completedBytes = await readFile(completedPath);
      assert.deepEqual(subject.canonicalJson(JSON.parse(completedBytes.toString('utf8'))), completedBytes);
      const remoteOutput = await lstat(remoteOutputPath, { bigint: true });
      const preparedOutput = await lstat(
        path.join(transactionRoot, 'authenticated-publisher0-output.prepared.json'), { bigint: true },
      );
      assert.equal(remoteOutput.dev, preparedOutput.dev);
      assert.equal(remoteOutput.ino, preparedOutput.ino);
      assert.equal(remoteOutput.nlink, 2n);
      await lstat(path.join(stateRoot, 'result.json'));
    } finally {
      await releasePublisher0TransportBarrier(fixture.sourceRoot, stage).catch(() => undefined);
      original?.kill('SIGKILL');
      recovery?.kill('SIGKILL');
      await new Promise((resolve) => setTimeout(resolve, 100));
      await cleanupSyntheticFixture(fixture.root);
    }
  }
});

for (const stage of [
  'remote-prepared-before-first-local-chunk',
  'before-last-local-chunk',
  'after-local-ack',
]) {
test(`round6 actual P0 keeps remote terminal output absent and survives broker plus outer death at ${stage}`, async () => {
    const fixture = await createActualCliFixture(`round6-p0-broker-death-${stage}`);
    const transportRoot = path.join(fixture.sourceRoot, 'publisher0-transport');
    const barrierPath = path.join(transportRoot, `${stage}.prepared.json`);
    const completedPath = path.join(transportRoot, 'completed.json');
    const transactionRoot = path.join(
      fixture.fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority', fixture.context.authority.commit,
      fixture.publisher0TransactionGenerationId,
    );
    const remoteOutputPath = path.join(transactionRoot, 'authenticated-publisher0-output.json');
    let original = null;
    let recovery = null;
    try {
      assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
      original = spawnActualCli(fixture.root, '--provision-vps-publisher0', {
        CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER: stage,
      });
      const originalResult = collectActualCli(original);
      await waitForFixturePath(barrierPath, original);
      const brokerPid = await waitForPublisher0BrokerPid(original);
      await assert.rejects(lstat(remoteOutputPath), { code: 'ENOENT' });
      process.kill(brokerPid, 'SIGKILL');
      original.kill('SIGKILL');
      const crashed = await originalResult;
      assert.equal(crashed.signal, 'SIGKILL');
      await releasePublisher0TransportBarrier(fixture.sourceRoot, stage);
      recovery = spawnActualCli(fixture.root, '--provision-vps-publisher0');
      const recoveryResult = collectActualCli(recovery);
      await waitForFixturePath(completedPath, recovery, 5_000);
      const completed = await recoveryResult;
      assert.equal(completed.status, 0, `${stage}: ${completed.stderr}`);
      const outputBytes = await readFile(remoteOutputPath);
      assert.deepEqual(subject.canonicalJson(JSON.parse(outputBytes.toString('utf8'))), outputBytes);
      const markerBytes = await readFile(path.join(fixture.root, 'fixed-bin', 'provision-vps-publisher0.ran'));
      assert.equal(markerBytes.length, 0);
    } finally {
      await releasePublisher0TransportBarrier(fixture.sourceRoot, stage).catch(() => undefined);
      original?.kill('SIGKILL');
      recovery?.kill('SIGKILL');
      await new Promise((resolve) => setTimeout(resolve, 100));
      await cleanupSyntheticFixture(fixture.root);
    }
});
}

for (const stage of [
  'remote-prepared-before-first-local-chunk',
  'before-last-local-chunk',
  'after-local-ack',
]) {
test(`round7 actual P0 session supervisor restarts the killed continuation worker at ${stage} without another SSH or effect`, async () => {
  const fixture = await createActualCliFixture(`round7-p0-continuation-death-${stage}`);
  const transportRoot = path.join(fixture.sourceRoot, 'publisher0-transport');
  const barrierPath = path.join(transportRoot, `${stage}.prepared.json`);
  let operation = null;
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    operation = spawnActualCli(fixture.root, '--provision-vps-publisher0', {
      CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER: stage,
    });
    const result = collectActualCli(operation);
    await waitForFixturePath(barrierPath, operation);
    const workerPid = await waitForFixtureProcessPid(
      fixture.root, '--internal-publisher0-transport-journal-worker', operation, 3_000,
    );
    process.kill(workerPid, 'SIGKILL');
    await releasePublisher0TransportBarrier(fixture.sourceRoot, stage);
    const completed = await result;
    assert.equal(
      completed.status, 0,
      `${stage}: ${completed.stderr}${JSON.stringify(await publisher0LifecycleDiagnostic(fixture.sourceRoot))}`,
    );
    const markerBytes = await readFile(path.join(fixture.root, 'fixed-bin', 'provision-vps-publisher0.ran'));
    assert.equal(markerBytes.length, 0);
    const transactionRoot = path.join(
      fixture.fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority', fixture.context.authority.commit,
      fixture.publisher0TransactionGenerationId,
    );
    await lstat(path.join(transactionRoot, 'authenticated-publisher0-output.json'));
  } finally {
    await releasePublisher0TransportBarrier(fixture.sourceRoot, stage).catch(() => undefined);
    operation?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});
}

for (const stage of [
  'remote-prepared-before-first-local-chunk',
  'before-last-local-chunk',
  'after-local-ack',
]) {
test(`round8 actual P0 broker restarts the killed session supervisor at ${stage} while the original transport survives`, async () => {
  const fixture = await createActualCliFixture(`round8-p0-session-supervisor-death-${stage}`);
  const transportRoot = path.join(fixture.sourceRoot, 'publisher0-transport');
  const barrierPath = path.join(transportRoot, `${stage}.prepared.json`);
  let operation = null;
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    operation = spawnActualCli(fixture.root, '--provision-vps-publisher0', {
      CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER: stage,
    });
    const result = collectActualCli(operation);
    await waitForFixturePath(barrierPath, operation);
    const supervisorPid = await waitForFixtureProcessPid(
      fixture.root, '--internal-publisher0-transport-session-supervisor', operation, 3_000,
    );
    const markerPath = path.join(fixture.root, 'fixed-bin', 'provision-vps-publisher0.ran');
    const transportBefore = await lstat(markerPath, { bigint: true });
    process.kill(supervisorPid, 'SIGKILL');
    const replacementPid = await waitForReplacementFixtureProcessPid(
      fixture.root, '--internal-publisher0-transport-session-supervisor', supervisorPid, operation, 3_000,
    );
    assert.notEqual(replacementPid, supervisorPid);
    await releasePublisher0TransportBarrier(fixture.sourceRoot, stage);
    const completed = await result;
    assert.equal(
      completed.status, 0,
      `${stage}: ${completed.stderr}${JSON.stringify(await publisher0LifecycleDiagnostic(fixture.sourceRoot))}`,
    );
    const transportAfter = await lstat(markerPath, { bigint: true });
    assert.equal(transportAfter.dev, transportBefore.dev);
    assert.equal(transportAfter.ino, transportBefore.ino);
    const commitDecision = await readFile(path.join(transportRoot, 'commit-decided.json'));
    assert.deepEqual(subject.canonicalJson(JSON.parse(commitDecision.toString('utf8'))), commitDecision);
  } finally {
    await releasePublisher0TransportBarrier(fixture.sourceRoot, stage).catch(() => undefined);
    operation?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});
}

for (const stage of [
  'remote-before-terminal-link',
  'remote-after-terminal-link-before-directory-fsync',
  'remote-after-directory-fsync-before-terminal-decision',
]) {
test(`round8 actual P0 terminal decision survives session supervisor death at ${stage} with one transport and one remote commit`, async () => {
  const fixture = await createActualCliFixture(`round8-p0-remote-terminal-${stage}`);
  const transportRoot = path.join(fixture.sourceRoot, 'publisher0-transport');
  const barrierPath = path.join(transportRoot, `${stage}.prepared.json`);
  const transactionRoot = path.join(
    fixture.fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority', fixture.context.authority.commit,
    fixture.publisher0TransactionGenerationId,
  );
  const remoteOutputPath = path.join(transactionRoot, 'authenticated-publisher0-output.json');
  let operation = null;
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    operation = spawnActualCli(fixture.root, '--provision-vps-publisher0', {
      CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER: stage,
    });
    const result = collectActualCli(operation);
    await waitForFixturePath(barrierPath, operation);
    const supervisorPid = await waitForFixtureProcessPid(
      fixture.root, '--internal-publisher0-transport-session-supervisor', operation, 3_000,
    );
    const markerPath = path.join(fixture.root, 'fixed-bin', 'provision-vps-publisher0.ran');
    const transportBefore = await lstat(markerPath, { bigint: true });
    process.kill(supervisorPid, 'SIGKILL');
    await waitForReplacementFixtureProcessPid(
      fixture.root, '--internal-publisher0-transport-session-supervisor', supervisorPid, operation, 3_000,
    );
    await releasePublisher0TransportBarrier(fixture.sourceRoot, stage);
    const completed = await result;
    assert.equal(
      completed.status, 0,
      `${stage}: ${completed.stderr}${JSON.stringify(await publisher0LifecycleDiagnostic(fixture.sourceRoot))}`,
    );
    const transportAfter = await lstat(markerPath, { bigint: true });
    assert.equal(transportAfter.dev, transportBefore.dev);
    assert.equal(transportAfter.ino, transportBefore.ino);
    const prepared = await lstat(
      path.join(transactionRoot, 'authenticated-publisher0-output.prepared.json'), { bigint: true },
    );
    const committed = await lstat(remoteOutputPath, { bigint: true });
    assert.equal(committed.dev, prepared.dev);
    assert.equal(committed.ino, prepared.ino);
    assert.equal(committed.nlink, 2n);
    const terminalDecision = await readFile(path.join(transportRoot, 'remote-terminal-decision.json'));
    assert.deepEqual(subject.canonicalJson(JSON.parse(terminalDecision.toString('utf8'))), terminalDecision);
  } finally {
    await releasePublisher0TransportBarrier(fixture.sourceRoot, stage).catch(() => undefined);
    operation?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});
}

test('round7 P0 freezes and reads back the complete PREPARED tree before ACK then terminally commits with one no-replace link', async () => {
  const fixture = await createActualCliFixture('round7-p0-prepared-single-commit');
  const stage = 'remote-prepared-before-first-local-chunk';
  const transportRoot = path.join(fixture.sourceRoot, 'publisher0-transport');
  const transactionRoot = path.join(
    fixture.fakeRemoteRoot, 'var/lib/agentempp/ci3-vps-authority', fixture.context.authority.commit,
    fixture.publisher0TransactionGenerationId,
  );
  const preparedPath = path.join(transactionRoot, 'authenticated-publisher0-output.prepared.json');
  const outputPath = path.join(transactionRoot, 'authenticated-publisher0-output.json');
  let operation = null;
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    operation = spawnActualCli(fixture.root, '--provision-vps-publisher0', {
      CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER: stage,
    });
    const result = collectActualCli(operation);
    await waitForFixturePath(path.join(transportRoot, `${stage}.prepared.json`), operation);
    assert.equal((await lstat(transactionRoot)).mode & 0o777, 0o555);
    assert.equal((await lstat(path.join(transactionRoot, 'publisher-input'))).mode & 0o777, 0o555);
    assert.equal((await lstat(preparedPath)).mode & 0o777, 0o444);
    await assert.rejects(lstat(outputPath), { code: 'ENOENT' });
    await releasePublisher0TransportBarrier(fixture.sourceRoot, stage);
    const completed = await result;
    assert.equal(completed.status, 0, completed.stderr);
    const prepared = await lstat(preparedPath, { bigint: true });
    const output = await lstat(outputPath, { bigint: true });
    assert.equal(output.dev, prepared.dev);
    assert.equal(output.ino, prepared.ino);
    assert.equal(output.nlink, 2n);
    assert.equal(prepared.nlink, 2n);
  } finally {
    await releasePublisher0TransportBarrier(fixture.sourceRoot, stage).catch(() => undefined);
    operation?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});

test('round4 outer P1 re-entry joins the original single supervisor after exact Phase A without a second prompt or Phase A invocation', async () => {
  const fixture = await createActualCliFixture('round4-p1-single-supervisor-recovery');
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const phaseAMarker = path.join(continuationRoot, 'publisher1-phase-a.settled');
  const supervisorMarker = path.join(continuationRoot, 'publisher1-supervisor.invocation');
  const phaseBPrepared = path.join(continuationRoot, 'publisher1-phase-b.prepared.json');
  const outerState = path.join(fixture.authorityRoot, 'state', 'provision-mac-publisher1');
  const phaseARoot = path.join(
    fixture.root, 'publisher1-installer-base', fixture.context.authority.commit,
    fixture.context.generations.controller,
  );
  const phaseBRoot = path.join(
    fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
    `bootstrap-${fixture.context.authority.manifest_sha256}`,
  );
  let original = null;
  let recovery = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    original = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
    });
    const originalResult = collectActualCli(original);
    const phaseAStat = await waitForFixturePath(phaseAMarker, original);
    assert.equal(phaseAStat.mode & 0o777, 0o600);
    await waitForFixturePath(phaseBPrepared, original);
    const supervisorBefore = await lstat(supervisorMarker, { bigint: true });
    assert.equal((await lstat(path.join(phaseARoot, 'runtime', 'ci3-publisher1-bootstrap-installer'))).mode & 0o777, 0o555);
    const bootstrapRequestPath = path.join(continuationRoot, 'publisher1-bootstrap.request.json');
    const bootstrapRequestBytes = await readFile(bootstrapRequestPath);
    assert.equal(await subject.validateExactPublisher1PhaseA({
      roots: { syntheticRoot: fixture.root }, context: fixture.context,
      canonicalRequest: {
        request: JSON.parse(bootstrapRequestBytes.toString('utf8')),
        bytes: bootstrapRequestBytes, request_path: bootstrapRequestPath,
      },
      artifactRoot: continuationRoot,
    }), 'PHASE_A_SETTLED_CONTINUING');
    await lstat(path.join(outerState, 'attempt.json'));
    await assert.rejects(lstat(path.join(outerState, 'result.json')), { code: 'ENOENT' });
    await assert.rejects(lstat(phaseBRoot), { code: 'ENOENT' });

    original.kill('SIGKILL');
    const crashed = await originalResult;
    assert.equal(crashed.signal, 'SIGKILL');
    recovery = spawnActualCli(fixture.root, '--provision-mac-publisher1');
    const recoveryResult = collectActualCli(recovery);
    await new Promise((resolve) => setTimeout(resolve, 100));
    await releasePublisher1PhaseB(continuationRoot);
    const recovered = await recoveryResult;
    assert.equal(recovered.status, 0, recovered.stderr);
    const supervisorAfter = await lstat(supervisorMarker, { bigint: true });
    assert.equal(supervisorAfter.dev, supervisorBefore.dev);
    assert.equal(supervisorAfter.ino, supervisorBefore.ino);
    await lstat(path.join(phaseBRoot, 'runtime', 'ci3-bridge-launcher.zsh'));
    await lstat(path.join(outerState, 'result.json'));
    await lstat(path.join(
      fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit,
      'operation-authority.publisher-request.json',
    ));
  } finally {
    await releasePublisher1PhaseB(continuationRoot).catch(() => undefined);
    original?.kill('SIGKILL');
    recovery?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});

test('round5 durable P1 service survives the privileged supervisor process death and resumes Phase B without another prompt or Phase A', async () => {
  const fixture = await createActualCliFixture('round5-p1-durable-supervisor-death');
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const serviceClaimPath = path.join(continuationRoot, 'publisher1-durable-phase-b.service.json');
  const serviceStartedPath = path.join(continuationRoot, 'publisher1-durable-phase-b.started.json');
  const serviceCompletedPath = path.join(continuationRoot, 'publisher1-durable-phase-b.completed.json');
  const phaseBPrepared = path.join(continuationRoot, 'publisher1-phase-b.prepared.json');
  const supervisorMarker = path.join(continuationRoot, 'publisher1-supervisor.invocation');
  const outerState = path.join(fixture.authorityRoot, 'state', 'provision-mac-publisher1');
  const phaseBRoot = path.join(
    fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
    `bootstrap-${fixture.context.authority.manifest_sha256}`,
  );
  let original = null;
  let recovery = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    original = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
      CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AFTER_SERVICE_REGISTRATION: '1',
    });
    const originalResult = collectActualCli(original);
    const serviceClaimStat = await waitForFixturePath(serviceClaimPath, original, 5_000);
    assert.equal(serviceClaimStat.mode & 0o777, 0o600);
    const supervisorBefore = await lstat(supervisorMarker, { bigint: true });
    const stopped = await originalResult;
    assert.equal(stopped.status, 1);
    assert.equal(stopped.signal, null);
    assert.equal(stopped.stderr, 'STOP_PRE_AUTHORITY mode=--provision-mac-publisher1 raw_values=false\n');
    await lstat(path.join(outerState, 'attempt.json'));
    await assert.rejects(lstat(path.join(outerState, 'result.json')), { code: 'ENOENT' });
    await assert.rejects(lstat(phaseBRoot), { code: 'ENOENT' });
    const bootstrapRequestPath = path.join(continuationRoot, 'publisher1-bootstrap.request.json');
    const bootstrapRequestBytes = await readFile(bootstrapRequestPath);
    assert.equal(await subject.validateExactPublisher1PhaseA({
      roots: { syntheticRoot: fixture.root }, context: fixture.context,
      canonicalRequest: {
        request: JSON.parse(bootstrapRequestBytes.toString('utf8')),
        bytes: bootstrapRequestBytes, request_path: bootstrapRequestPath,
      },
      artifactRoot: continuationRoot,
    }), 'PHASE_A_SETTLED_CONTINUING');

    recovery = spawnActualCli(fixture.root, '--provision-mac-publisher1');
    const recoveryResult = collectActualCli(recovery);
    try {
      await waitForFixturePath(serviceStartedPath, recovery, 5_000);
    } catch (error) {
      const early = await recoveryResult;
      const present = {};
      for (const [name, file] of Object.entries({
        claim: serviceClaimPath,
        definition: path.join(continuationRoot, 'publisher1-durable-phase-b.launchd.plist'),
        registration: path.join(continuationRoot, 'publisher1-durable-phase-b.registration.json'),
        started: serviceStartedPath,
        failed: path.join(continuationRoot, 'publisher1-durable-phase-b.failed.json'),
      })) present[name] = await lstat(file).then(() => true, () => false);
      assert.fail(`durable-worker stage=started status=${early.status} signal=${early.signal ?? 'none'} stderr=${early.stderr.trim()} files=${JSON.stringify(present)} cause=${error.message}`);
    }
    await waitForFixturePath(phaseBPrepared, recovery, 5_000);
    await releasePublisher1PhaseB(continuationRoot);
    const recovered = await recoveryResult;
    assert.equal(recovered.status, 0, recovered.stderr);

    const supervisorAfter = await lstat(supervisorMarker, { bigint: true });
    assert.equal(supervisorAfter.dev, supervisorBefore.dev);
    assert.equal(supervisorAfter.ino, supervisorBefore.ino);
    const serviceClaimBytes = await readFile(serviceClaimPath);
    const serviceClaim = JSON.parse(serviceClaimBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(serviceClaim), serviceClaimBytes);
    assert.equal(serviceClaim.purpose, 'CI3_PUBLISHER1_DURABLE_PHASE_B_SERVICE_V1');
    assert.equal(serviceClaim.service_kind, 'VERSION_ADDRESSED_PERSISTENT_CONTINUATION');
    assert.equal(serviceClaim.admin_prompt_budget, 1);
    assert.equal(serviceClaim.phase_a_attempt, 1);
    assert.equal(serviceClaim.retry, false);
    assert.equal(serviceClaim.raw_values, false);
    assert.equal(serviceClaim.immutable_request_sha256, subject.sha256(await readFile(
      path.join(continuationRoot, 'publisher1-immutable-installer.request.json'),
    )));
    const definitionBytes = await readFile(path.join(continuationRoot, 'publisher1-durable-phase-b.launchd.plist'));
    const registrationBytes = await readFile(path.join(continuationRoot, 'publisher1-durable-phase-b.registration.json'));
    const registration = JSON.parse(registrationBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(registration), registrationBytes);
    assert.equal(registration.service_claim_sha256, subject.sha256(serviceClaimBytes));
    assert.equal(registration.service_definition_sha256, subject.sha256(definitionBytes));
    assert.equal(registration.persistence, 'SYNTHETIC_VERSION_ADDRESSED_ACTIVATION_OWNER');
    assert.equal(registration.status, 'REGISTERED');
    assert.equal(registration.admin_prompt_budget, 1);
    assert.equal(registration.phase_a_target_writes, 0);
    assert.doesNotMatch(definitionBytes.toString('utf8'), /<key>RunAtLoad<\/key>/u);
    assert.doesNotMatch(definitionBytes.toString('utf8'), /<key>KeepAlive<\/key>/u);
    assert.doesNotMatch(definitionBytes.toString('utf8'), /<key>SuccessfulExit<\/key>/u);
    assert.match(definitionBytes.toString('utf8'), /--durable-immutable-bootstrap-phase-b/u);
    const activationOwnerDefinitionBytes = await readFile(path.join(
      continuationRoot, 'publisher1-durable-phase-b.activation-owner.plist',
    ));
    assert.match(
      activationOwnerDefinitionBytes.toString('utf8'),
      /--durable-immutable-bootstrap-activation-owner/u,
    );
    assert.match(activationOwnerDefinitionBytes.toString('utf8'), /<key>KeepAlive<\/key>/u);
    const completedBytes = await readFile(serviceCompletedPath);
    const completed = JSON.parse(completedBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(completed), completedBytes);
    assert.equal(completed.service_claim_sha256, subject.sha256(serviceClaimBytes));
    assert.equal(completed.terminal_state, 'PHASE_B_SETTLED');
    const runClaimPath = path.join(continuationRoot, 'publisher1-durable-phase-b.run-claim.json');
    const effectEntryPath = path.join(continuationRoot, 'publisher1-durable-phase-b.effect-entry.json');
    const runClaimBefore = await lstat(runClaimPath, { bigint: true });
    const effectEntryBefore = await lstat(effectEntryPath, { bigint: true });
    const envelopePath = path.join(continuationRoot, 'publisher1-immutable-installer.request.json');
    const envelopeBytes = await readFile(envelopePath);
    const installedPath = path.join(
      fixture.root, 'publisher1-installer-base', fixture.context.authority.commit,
      fixture.context.generations.controller, 'runtime', 'ci3-publisher1-bootstrap-installer',
    );
    for (const equivalent of ['reload', 'reinvoke']) {
      const relaunched = spawnSync(installedPath, [
        '--durable-immutable-bootstrap-phase-b', envelopePath, subject.sha256(envelopeBytes),
        serviceClaimPath, subject.sha256(serviceClaimBytes),
      ], {
        encoding: 'utf8', timeout: 10_000, maxBuffer: 64 * 1024,
        env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin',
          CI3_SYNTHETIC_MAIN_ROOT: fixture.root,
          CI3_SYNTHETIC_FROZEN_PROJECTION_PATH: path.join(fixture.sourceRoot, 'frozen-authority-projection.json'),
          CI3_SYNTHETIC_INSTALLER_BASE: path.join(fixture.root, 'publisher1-installer-base'),
          CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1' },
      });
      assert.equal(relaunched.status, 0, `${equivalent}: ${relaunched.stderr}`);
      assert.equal(relaunched.stderr, 'TERMINAL_ALREADY_SETTLED\n');
      for (const [file, before] of [[runClaimPath, runClaimBefore], [effectEntryPath, effectEntryBefore]]) {
        const after = await lstat(file, { bigint: true });
        assert.equal(after.dev, before.dev);
        assert.equal(after.ino, before.ino);
        assert.equal(after.mtimeNs, before.mtimeNs);
      }
    }
    await lstat(path.join(phaseBRoot, 'runtime', 'ci3-bridge-launcher.zsh'));
    await lstat(path.join(outerState, 'result.json'));
  } finally {
    await releasePublisher1PhaseB(continuationRoot).catch(() => undefined);
    original?.kill('SIGKILL');
    recovery?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});

for (const registrationStage of ['CLAIM', 'DEFINITION', 'BOOTSTRAP', 'REGISTRATION']) {
test(`round6 P1 registration survives supervisor death at ${registrationStage} without a second prompt, Phase A, or worker invocation`, async () => {
  const fixture = await createActualCliFixture(`round6-p1-registration-${registrationStage.toLowerCase()}`);
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const registrationPrepared = path.join(
    continuationRoot,
    `publisher1-durable-registration-${registrationStage.toLowerCase()}.prepared.json`,
  );
  const phaseBPrepared = path.join(continuationRoot, 'publisher1-phase-b.prepared.json');
  const supervisorMarker = path.join(continuationRoot, 'publisher1-supervisor.invocation');
  const outerState = path.join(fixture.authorityRoot, 'state', 'provision-mac-publisher1');
  const phaseBRoot = path.join(
    fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
    `bootstrap-${fixture.context.authority.manifest_sha256}`,
  );
  let original = null;
  let recovery = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    original = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
      CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE: registrationStage,
    });
    const originalResult = collectActualCli(original);
    await waitForFixturePath(registrationPrepared, original, 5_000);
    const supervisorBefore = await lstat(supervisorMarker, { bigint: true });
    const stopped = await originalResult;
    assert.equal(stopped.status, 1);
    assert.equal(stopped.signal, null);
    assert.equal(stopped.stderr, 'STOP_PRE_AUTHORITY mode=--provision-mac-publisher1 raw_values=false\n');
    await lstat(path.join(outerState, 'attempt.json'));
    await assert.rejects(lstat(path.join(outerState, 'result.json')), { code: 'ENOENT' });
    await assert.rejects(lstat(phaseBRoot), { code: 'ENOENT' });

    recovery = spawnActualCli(fixture.root, '--provision-mac-publisher1');
    const recoveryResult = collectActualCli(recovery);
    await releasePublisher1DurableRegistration(continuationRoot, registrationStage);
    await waitForFixturePath(phaseBPrepared, recovery, 10_000);
    await releasePublisher1PhaseB(continuationRoot);
    const recovered = await recoveryResult;
    if (recovered.status !== 0) {
      const diagnostic = {};
      for (const [name, file] of Object.entries({
        registration: path.join(continuationRoot, 'publisher1-durable-phase-b.registration.json'),
        serviceStarted: path.join(continuationRoot, 'publisher1-durable-phase-b.started.json'),
        serviceCompleted: path.join(continuationRoot, 'publisher1-durable-phase-b.completed.json'),
        serviceFailed: path.join(continuationRoot, 'publisher1-durable-phase-b.failed.json'),
        bootstrapResult: path.join(
          fixture.root, 'publisher1-state-base', fixture.context.authority.commit,
          fixture.context.generations.controller, 'publisher1-bootstrap.result.json',
        ),
        outerResult: path.join(outerState, 'result.json'),
      })) diagnostic[name] = await lstat(file).then(() => true, () => false);
      assert.equal(recovered.status, 0, `${recovered.stderr.trim()} state=${JSON.stringify(diagnostic)}`);
    }
    const supervisorAfter = await lstat(supervisorMarker, { bigint: true });
    assert.equal(supervisorAfter.dev, supervisorBefore.dev);
    assert.equal(supervisorAfter.ino, supervisorBefore.ino);
    await lstat(path.join(phaseBRoot, 'runtime', 'ci3-bridge-launcher.zsh'));
    await lstat(path.join(outerState, 'result.json'));
  } finally {
    await releasePublisher1DurableRegistration(continuationRoot, registrationStage).catch(() => undefined);
    await releasePublisher1PhaseB(continuationRoot).catch(() => undefined);
    original?.kill('SIGKILL');
    recovery?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});
}

for (const registrationStage of [
  'CLAIM', 'DEFINITION', 'INVOCATION', 'PRE_BOOTSTRAP', 'POST_BOOTSTRAP', 'PRE_REGISTRATION',
]) {
test(`round7 P1 registration survives actual registrar death at ${registrationStage} in the persistent state machine`, async () => {
  const fixture = await createActualCliFixture(`round7-p1-registrar-death-${registrationStage.toLowerCase()}`);
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const barrierPath = path.join(
    continuationRoot, `publisher1-durable-registration-${registrationStage.toLowerCase()}.prepared.json`,
  );
  let original = null;
  let recovery = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    original = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
      CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE: registrationStage,
    });
    const originalResult = collectActualCli(original);
    await waitForFixturePath(barrierPath, original, 10_000);
    assert.equal(
      fixtureHasProcessMode(fixture.root, '--durable-immutable-bootstrap-phase-b'), false,
      'the worker must not exist before the registrar has durably registered and explicitly kickstarted it',
    );
    await assert.rejects(
      lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.run-claim.json')),
      { code: 'ENOENT' },
    );
    await assert.rejects(
      lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.effect-entry.json')),
      { code: 'ENOENT' },
    );
    const registrarPid = await waitForFixtureProcessPid(
      fixture.root, '--durable-immutable-bootstrap-registrar', original,
    );
    process.kill(registrarPid, 'SIGKILL');
    await releasePublisher1DurableRegistration(continuationRoot, registrationStage);
    const stopped = await originalResult;
    assert.equal(stopped.status, 1);
    recovery = spawnActualCli(fixture.root, '--provision-mac-publisher1');
    const recoveryResult = collectActualCli(recovery, 10_000);
    await waitForFixturePath(
      path.join(continuationRoot, 'publisher1-phase-b.prepared.json'), recovery, 5_000,
    );
    await releasePublisher1PhaseB(continuationRoot);
    const recovered = await recoveryResult;
    assert.equal(recovered.status, 0, recovered.stderr);
    const runClaimBytes = await readFile(path.join(
      continuationRoot, 'publisher1-durable-phase-b.run-claim.json',
    ));
    const effectEntryBytes = await readFile(path.join(
      continuationRoot, 'publisher1-durable-phase-b.effect-entry.json',
    ));
    assert.deepEqual(subject.canonicalJson(JSON.parse(runClaimBytes)), runClaimBytes);
    assert.deepEqual(subject.canonicalJson(JSON.parse(effectEntryBytes)), effectEntryBytes);
    assert.equal(fixtureHasProcessMode(fixture.root, '--durable-immutable-bootstrap-phase-b'), false);
  } finally {
    await releasePublisher1DurableRegistration(continuationRoot, registrationStage).catch(() => undefined);
    await releasePublisher1PhaseB(continuationRoot).catch(() => undefined);
    original?.kill('SIGKILL');
    recovery?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});
}

for (const workerStage of ['RUN_CLAIM', 'PRE_EFFECT_ENTRY', 'POST_EFFECT_ENTRY', 'PRE_TERMINAL']) {
test(`round8 P1 registrar recovers actual worker death at ${workerStage} without a second kickstart or effect entry`, async () => {
  const fixture = await createActualCliFixture(`round8-p1-worker-death-${workerStage.toLowerCase()}`);
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const workerSlug = workerStage.toLowerCase().replaceAll('_', '-');
  const workerBarrier = path.join(
    continuationRoot, `publisher1-durable-worker-${workerSlug}.prepared.json`,
  );
  let operation = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    operation = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
      CI3_SYNTHETIC_P1_WORKER_BARRIER_STAGE: workerStage,
    });
    const result = collectActualCli(operation, 20_000);
    if (workerStage !== 'RUN_CLAIM') {
      await waitForFixturePath(
        path.join(continuationRoot, 'publisher1-phase-b.prepared.json'), operation, 10_000,
      );
      await releasePublisher1PhaseB(continuationRoot);
    }
    await waitForFixturePath(workerBarrier, operation, 10_000);
    const workerPid = await waitForFixtureProcessPid(
      fixture.root, '--durable-immutable-bootstrap-phase-b', operation, 3_000,
    );
    process.kill(workerPid, 'SIGKILL');
    await releasePublisher1DurableWorker(continuationRoot, workerStage);
    if (workerStage === 'RUN_CLAIM') {
      await waitForFixturePath(
        path.join(continuationRoot, 'publisher1-phase-b.prepared.json'), operation, 10_000,
      );
      await releasePublisher1PhaseB(continuationRoot);
    }
    const settled = await result;
    const preEffect = ['RUN_CLAIM', 'PRE_EFFECT_ENTRY'].includes(workerStage);
    const durableEntries = (await readdir(continuationRoot)).filter((entry) => (
      entry.startsWith('publisher1-durable-phase-b.')
      || entry.startsWith('publisher1-durable-worker-')
    )).sort();
    assert.equal(
      settled.status, preEffect ? 0 : 1,
      `${workerStage}: ${settled.stderr} entries=${JSON.stringify(durableEntries)}`,
    );
    const kickstartBytes = await readFile(path.join(
      continuationRoot, 'publisher1-durable-phase-b.kickstart-decided.json',
    ));
    const kickstart = JSON.parse(kickstartBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(kickstart), kickstartBytes);
    assert.equal(kickstart.kickstart_invocations, 1);
    const workerLaunches = (await readdir(continuationRoot)).filter((entry) => (
      /^publisher1-durable-phase-b\.worker-launch-[0-9]+\.json$/u.test(entry)
    ));
    assert.equal(workerLaunches.length, preEffect ? 2 : 1);
    const effectEntry = await lstat(
      path.join(continuationRoot, 'publisher1-durable-phase-b.effect-entry.json'), { bigint: true },
    );
    assert.equal(effectEntry.nlink, 1n);
    if (preEffect) {
      await lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.completed.json'));
    } else {
      await lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.stop-partial.json'));
      await assert.rejects(
        lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.completed.json')),
        { code: 'ENOENT' },
      );
    }
  } finally {
    await releasePublisher1DurableWorker(continuationRoot, workerStage).catch(() => undefined);
    await releasePublisher1PhaseB(continuationRoot).catch(() => undefined);
    operation?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});
}

test('round8 P1 registrar death after kickstart joins the original worker and never kickstarts twice', async () => {
  const fixture = await createActualCliFixture('round8-p1-registrar-post-kickstart');
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const registrationStage = 'POST_KICKSTART';
  const barrierPath = path.join(
    continuationRoot, 'publisher1-durable-registration-post_kickstart.prepared.json',
  );
  let original = null;
  let recovery = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    original = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
      CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE: registrationStage,
    });
    const originalResult = collectActualCli(original, 20_000);
    await waitForFixturePath(barrierPath, original, 10_000);
    const registrarPid = await waitForFixtureProcessPid(
      fixture.root, '--durable-immutable-bootstrap-registrar', original,
    );
    const workerPid = await waitForFixtureProcessPid(
      fixture.root, '--durable-immutable-bootstrap-phase-b', original,
    );
    process.kill(registrarPid, 'SIGKILL');
    await releasePublisher1DurableRegistration(continuationRoot, registrationStage);
    const stopped = await originalResult;
    assert.equal(stopped.status, 1);
    assert.doesNotThrow(() => process.kill(workerPid, 0));
    recovery = spawnActualCli(fixture.root, '--provision-mac-publisher1');
    const recoveryResult = collectActualCli(recovery, 20_000);
    await waitForFixturePath(
      path.join(continuationRoot, 'publisher1-phase-b.prepared.json'), recovery, 10_000,
    );
    await releasePublisher1PhaseB(continuationRoot);
    const recovered = await recoveryResult;
    assert.equal(recovered.status, 0, recovered.stderr);
    const kickstart = JSON.parse((await readFile(path.join(
      continuationRoot, 'publisher1-durable-phase-b.kickstart-decided.json',
    ))).toString('utf8'));
    assert.equal(kickstart.kickstart_invocations, 1);
    const workerLaunches = (await readdir(continuationRoot)).filter((entry) => (
      /^publisher1-durable-phase-b\.worker-launch-[0-9]+\.json$/u.test(entry)
    ));
    assert.equal(workerLaunches.length, 1);
  } finally {
    await releasePublisher1DurableRegistration(continuationRoot, registrationStage).catch(() => undefined);
    await releasePublisher1PhaseB(continuationRoot).catch(() => undefined);
    original?.kill('SIGKILL');
    recovery?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});

for (const activationStage of ['PRE_SIGNAL', 'POST_ACCEPT_PRE_RECEIPT']) {
test(`round9 P1 registrar death at ${activationStage} rejoins one activation owner and one physical kickstart`, async () => {
  const fixture = await createActualCliFixture(`round9-p1-activation-${activationStage.toLowerCase()}`);
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const stageSlug = activationStage.toLowerCase().replaceAll('_', '-');
  const barrierPath = path.join(
    continuationRoot, `publisher1-durable-activation-${stageSlug}.prepared.json`,
  );
  let operation = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    operation = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
      CI3_SYNTHETIC_P1_ACTIVATION_BARRIER_STAGE: activationStage,
    });
    const result = collectActualCli(operation, 30_000);
    try {
      await waitForFixturePath(barrierPath, operation, 10_000);
    } catch (error) {
      const durableEntries = (await readdir(continuationRoot).catch(() => [])).filter((entry) => (
        entry.startsWith('publisher1-durable-')
      )).sort();
      assert.fail(`${error.message}; durable_entries=${JSON.stringify(durableEntries)}`);
    }
    const ownerReadyPath = path.join(
      continuationRoot, 'publisher1-durable-phase-b.activation-owner-ready.json',
    );
    const signalPath = path.join(
      continuationRoot, 'publisher1-durable-phase-b.kickstart-decided.json',
    );
    const physicalKickstartPath = path.join(
      continuationRoot, 'publisher1-durable-phase-b.physical-kickstart.json',
    );
    const firstWorkerLaunchPath = path.join(
      continuationRoot, 'publisher1-durable-phase-b.worker-launch-1.json',
    );
    await lstat(ownerReadyPath);
    await assert.rejects(
      lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.effect-entry.json')),
      { code: 'ENOENT' },
    );
    if (activationStage === 'PRE_SIGNAL') {
      await assert.rejects(lstat(signalPath), { code: 'ENOENT' });
      await assert.rejects(lstat(physicalKickstartPath), { code: 'ENOENT' });
      await assert.rejects(lstat(firstWorkerLaunchPath), { code: 'ENOENT' });
    } else {
      await lstat(signalPath);
      const acceptedBytes = await readFile(physicalKickstartPath);
      const accepted = JSON.parse(acceptedBytes.toString('utf8'));
      assert.deepEqual(subject.canonicalJson(accepted), acceptedBytes);
      assert.equal(accepted.executable_kickstart_invocations, 1);
      await assert.rejects(lstat(firstWorkerLaunchPath), { code: 'ENOENT' });
    }
    const ownerPid = await waitForFixtureProcessPid(
      fixture.root, '--durable-immutable-bootstrap-activation-owner', operation,
    );
    const registrarPid = await waitForFixtureProcessPid(
      fixture.root, '--durable-immutable-bootstrap-registrar', operation,
    );
    process.kill(registrarPid, 'SIGKILL');
    const replacementRegistrarPid = await waitForReplacementFixtureProcessPid(
      fixture.root, '--durable-immutable-bootstrap-registrar', registrarPid, operation, 10_000,
    );
    assert.notEqual(replacementRegistrarPid, registrarPid);
    assert.doesNotThrow(() => process.kill(ownerPid, 0));
    await releasePublisher1Activation(continuationRoot, activationStage);
    await waitForFixturePath(
      path.join(continuationRoot, 'publisher1-phase-b.prepared.json'), operation, 10_000,
    );
    await releasePublisher1PhaseB(continuationRoot);
    const settled = await result;
    assert.equal(settled.status, 0, settled.stderr);

    const ownerReadyBytes = await readFile(ownerReadyPath);
    const ownerReady = JSON.parse(ownerReadyBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(ownerReady), ownerReadyBytes);
    assert.equal(ownerReady.activation_owner_launches, 1);
    const physicalKickstartBytes = await readFile(physicalKickstartPath);
    const physicalKickstart = JSON.parse(physicalKickstartBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(physicalKickstart), physicalKickstartBytes);
    assert.equal(physicalKickstart.executable_kickstart_invocations, 1);
    const workerLaunches = (await readdir(continuationRoot)).filter((entry) => (
      /^publisher1-durable-phase-b\.worker-launch-[0-9]+\.json$/u.test(entry)
    ));
    assert.equal(workerLaunches.length, 1);
    const effectEntry = await lstat(
      path.join(continuationRoot, 'publisher1-durable-phase-b.effect-entry.json'), { bigint: true },
    );
    assert.equal(effectEntry.nlink, 1n);
    await lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.completed.json'));
  } finally {
    await releasePublisher1Activation(continuationRoot, activationStage).catch(() => undefined);
    await releasePublisher1PhaseB(continuationRoot).catch(() => undefined);
    operation?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});
}

test('round6 one-shot durable P1 records exactly one worker invocation and does not relaunch after terminal failure', async () => {
  const fixture = await createActualCliFixture('round6-p1-one-shot-failure');
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const phaseBPrepared = path.join(continuationRoot, 'publisher1-phase-b.prepared.json');
  const invocationPath = path.join(continuationRoot, 'publisher1-durable-phase-b.invocation.json');
  const failedPath = path.join(continuationRoot, 'publisher1-durable-phase-b.failed.json');
  let original = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    original = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
    });
    const originalResult = collectActualCli(original);
    await waitForFixturePath(phaseBPrepared, original, 10_000);
    const invocationBefore = await lstat(invocationPath, { bigint: true });
    const invocationBytes = await readFile(invocationPath);
    const invocation = JSON.parse(invocationBytes.toString('utf8'));
    assert.deepEqual(subject.canonicalJson(invocation), invocationBytes);
    assert.equal(invocation.purpose, 'CI3_PUBLISHER1_DURABLE_PHASE_B_WORKER_INVOCATION_V1');
    assert.equal(invocation.worker_invocations, 1);
    assert.equal(invocation.attempt, 1);
    assert.equal(invocation.retry, false);
    assert.equal(invocation.raw_values, false);
    await rejectPublisher1PhaseB(continuationRoot);
    const stopped = await originalResult;
    assert.equal(stopped.status, 1);
    assert.equal(stopped.stderr, 'STOP_PRE_AUTHORITY mode=--provision-mac-publisher1 raw_values=false\n');
    await waitForFixturePath(failedPath, original).catch(async () => await lstat(failedPath));
    await new Promise((resolve) => setTimeout(resolve, 250));
    const invocationAfter = await lstat(invocationPath, { bigint: true });
    assert.equal(invocationAfter.dev, invocationBefore.dev);
    assert.equal(invocationAfter.ino, invocationBefore.ino);
    assert.deepEqual(await readFile(invocationPath), invocationBytes);
    const definition = await readFile(path.join(continuationRoot, 'publisher1-durable-phase-b.launchd.plist'), 'utf8');
    assert.doesNotMatch(definition, /<key>RunAtLoad<\/key>/u);
    assert.doesNotMatch(definition, /<key>KeepAlive<\/key>|<key>SuccessfulExit<\/key>/u);
    const runClaimPath = path.join(continuationRoot, 'publisher1-durable-phase-b.run-claim.json');
    const effectEntryPath = path.join(continuationRoot, 'publisher1-durable-phase-b.effect-entry.json');
    const runClaimBefore = await lstat(runClaimPath, { bigint: true });
    await assert.rejects(lstat(effectEntryPath), { code: 'ENOENT' });
    await lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.service-settled.json'));
    const envelopePath = path.join(continuationRoot, 'publisher1-immutable-installer.request.json');
    const envelopeBytes = await readFile(envelopePath);
    const installedPath = path.join(
      fixture.root, 'publisher1-installer-base', fixture.context.authority.commit,
      fixture.context.generations.controller, 'runtime', 'ci3-publisher1-bootstrap-installer',
    );
    const claimPath = path.join(continuationRoot, 'publisher1-durable-phase-b.service.json');
    const terminalReloadEnvironment = {
      HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin',
      CI3_SYNTHETIC_MAIN_ROOT: fixture.root,
      CI3_SYNTHETIC_FROZEN_PROJECTION_PATH: path.join(fixture.sourceRoot, 'frozen-authority-projection.json'),
      CI3_SYNTHETIC_INSTALLER_BASE: path.join(fixture.root, 'publisher1-installer-base'),
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
    };
    for (const equivalent of ['reload', 'reinvoke']) {
      const relaunched = spawnSync(installedPath, [
        '--durable-immutable-bootstrap-phase-b', envelopePath, subject.sha256(envelopeBytes),
        claimPath, subject.sha256(await readFile(claimPath)),
      ], { encoding: 'utf8', env: terminalReloadEnvironment, timeout: 10_000, maxBuffer: 64 * 1024 });
      assert.equal(relaunched.status, 0, `${equivalent}: ${relaunched.stderr}`);
      assert.equal(relaunched.stderr, 'TERMINAL_ALREADY_SETTLED\n');
      const runClaimAfter = await lstat(runClaimPath, { bigint: true });
      assert.equal(runClaimAfter.dev, runClaimBefore.dev);
      assert.equal(runClaimAfter.ino, runClaimBefore.ino);
      assert.equal(runClaimAfter.mtimeNs, runClaimBefore.mtimeNs);
      await assert.rejects(lstat(effectEntryPath), { code: 'ENOENT' });
    }
    await assert.rejects(lstat(path.join(continuationRoot, 'publisher1-durable-phase-b.completed.json')), { code: 'ENOENT' });
  } finally {
    original?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});

test('round4 outer P1 re-entry rejects a partial Phase B without spawning another supervisor', async () => {
  const fixture = await createActualCliFixture('round4-p1-partial-phase-b-stop');
  const continuationRoot = path.join(fixture.sourceRoot, 'publisher1-produced');
  const phaseBPrepared = path.join(continuationRoot, 'publisher1-phase-b.prepared.json');
  const supervisorMarker = path.join(continuationRoot, 'publisher1-supervisor.invocation');
  const outerState = path.join(fixture.authorityRoot, 'state', 'provision-mac-publisher1');
  let original = null;
  try {
    for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass']) {
      const result = runActualCli(fixture.root, mode);
      assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    }
    original = spawnActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1',
    });
    const originalResult = collectActualCli(original);
    await waitForFixturePath(phaseBPrepared, original, 15_000);
    const supervisorBefore = await lstat(supervisorMarker, { bigint: true });
    const partialStateRoot = path.join(
      fixture.root, 'publisher1-state-base', fixture.context.authority.commit,
      fixture.context.generations.controller,
    );
    await mkdir(partialStateRoot, { recursive: true, mode: 0o700 });
    await chmod(partialStateRoot, 0o700);
    for (let repetition = 0; repetition < 3; repetition += 1) {
      const rejected = runActualCli(fixture.root, '--provision-mac-publisher1');
      assert.equal(rejected.status, 1);
      assert.equal(rejected.stderr, 'STOP_PRE_AUTHORITY mode=--provision-mac-publisher1 raw_values=false\n');
      const supervisorAfter = await lstat(supervisorMarker, { bigint: true });
      assert.equal(supervisorAfter.dev, supervisorBefore.dev);
      assert.equal(supervisorAfter.ino, supervisorBefore.ino);
      await assert.rejects(lstat(path.join(outerState, 'result.json')), { code: 'ENOENT' });
    }
    await releasePublisher1PhaseB(continuationRoot);
    const stoppedOriginal = await originalResult;
    assert.equal(stoppedOriginal.status, 1);
    assert.equal(stoppedOriginal.stderr, 'STOP_PRE_AUTHORITY mode=--provision-mac-publisher1 raw_values=false\n');
    await assert.rejects(lstat(path.join(outerState, 'result.json')), { code: 'ENOENT' });
  } finally {
    await releasePublisher1PhaseB(continuationRoot).catch(() => undefined);
    original?.kill('SIGKILL');
    await new Promise((resolve) => setTimeout(resolve, 100));
    await cleanupSyntheticFixture(fixture.root);
  }
});

test('successor receive creates request before local human V2 and materializes the sixteenth leaf without a receiver-output fixture', async () => {
  const fixture = await createActualCliFixture('successor-receiver-request-human');
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
    const requestRoot = path.join(fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit);
    const receiverRoot = path.join(requestRoot, 'receiver', fixture.context.generations.remote,
      fixture.context.generations.controller, fixture.receiverManifestSha256);
    const authorizationRequestPath = path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-human-authorization.request.json');
    await assert.rejects(lstat(authorizationRequestPath));
    await assert.rejects(lstat(path.join(receiverRoot, 'human-authorization.payload')));
    const receive = runActualCli(fixture.root, '--receive-vps-pass');
    if (receive.status !== 0) {
      const diagnostic = {};
      for (const [name, file] of Object.entries({
        installerAuthority: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-installer.compile-authority.json'),
        installerReceipt: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-installer.compile-receipt.json'),
        installerBinary: path.join(fixture.sourceRoot, 'publisher1-produced', 'runtime', 'ci3-publisher1-bootstrap-installer'),
        authorizationRequest: authorizationRequestPath,
        promptAttempt: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-human-authorization.prompt-attempt.json'),
        humanLeaf: path.join(receiverRoot, 'human-authorization.payload'),
        descriptor: path.join(requestRoot, 'publisher1-transaction.request.json'),
        writerReceipt: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-writer.compile-receipt.json'),
        bootstrap: path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-bootstrap.request.json'),
      })) diagnostic[name] = await lstat(file).then(() => true, () => false);
      assert.equal(receive.status, 0, `${receive.stderr}${JSON.stringify(diagnostic)}`);
    }
    const authorizationRequestBytes = await readFile(authorizationRequestPath);
    const authorizationRequest = JSON.parse(authorizationRequestBytes.toString('utf8'));
    assert.equal(authorizationRequest.purpose, 'CI3_HUMAN_AUTHORIZATION_REQUEST_V2');
    assert.equal(authorizationRequest.prompt_budget, 1);
    const humanBytes = await readFile(path.join(receiverRoot, 'human-authorization.payload'));
    const human = JSON.parse(humanBytes.toString('utf8'));
    assert.equal(human.purpose, 'CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V2');
    assert.equal(human.authorization_request_sha256, subject.sha256(authorizationRequestBytes));
    assert.equal(human.prompt_budget, 1);
    assert.equal(human.publisher_installer_git_path, 'scripts/ci3/ci3-publisher1-bootstrap-installer.swift');
    assert.match(human.publisher_installer_git_blob_oid, /^[a-f0-9]{40}$/);
    assert.equal((await lstat(path.join(requestRoot, 'publisher1-transaction.request.json'))).mode & 0o777, 0o600);
    await assert.rejects(lstat(path.join(fixture.sourceRoot, 'receiver-output', 'human-authorization.payload')));
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('successor actual chain rejects bound invalid launcher bytes before a semantic receipt or Phase A', async () => {
  const fixture = await createActualCliFixture('successor-real-semantic-rejection', { semanticInvalidLauncherAuthority: true });
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    const publisher0 = runActualCli(fixture.root, '--provision-vps-publisher0');
    assert.equal(publisher0.status, 1);
    assert.equal(publisher0.stderr, 'VPS_PUBLISHER0_PROVISION\n');
    const receive = runActualCli(fixture.root, '--receive-vps-pass');
    assert.equal(receive.status, 1);
    await assert.rejects(lstat(path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-semantic-preflight.receipt.json')));
    await assert.rejects(lstat(path.join(fixture.root, 'publisher1-installer-base', fixture.context.authority.commit,
      fixture.context.generations.controller)));
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('successor privileged boundary reobserves request receiver and all sixteen leaves after preflight before any target write', async () => {
  const fixture = await createActualCliFixture('successor-post-preflight-leaf-swap');
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
    assert.equal(runActualCli(fixture.root, '--receive-vps-pass').status, 0);
    const publisher1 = runActualCli(fixture.root, '--provision-mac-publisher1', {
      CI3_SYNTHETIC_POST_PREFLIGHT_SWAP_ROLE: 'node-runtime',
    });
    assert.equal(publisher1.status, 1);
    assert.equal(publisher1.stderr, 'STOP_PRE_AUTHORITY mode=--provision-mac-publisher1 raw_values=false\n');
    assert.equal((await lstat(path.join(fixture.sourceRoot, 'publisher1-produced',
      'publisher1-semantic-preflight.receipt.json'))).mode & 0o777, 0o600);
    await assert.rejects(lstat(path.join(fixture.authorityRoot, 'state', 'provision-mac-publisher1', 'attempt.json')));
    await assert.rejects(lstat(path.join(fixture.root, 'publisher1-installer-base', fixture.context.authority.commit,
      fixture.context.generations.controller)));
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('successor rejects an alternate installer source even when its mutable sidecar self-authorizes the bytes before Phase A', async () => {
  const fixture = await createActualCliFixture('successor-installer-independent-digest');
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
    assert.equal(runActualCli(fixture.root, '--receive-vps-pass').status, 0);
    const installerPath = path.join(fixture.sourceRoot, 'publisher1-input', 'installer.swift');
    const authorityPath = path.join(fixture.sourceRoot, 'publisher1-input', 'installer.authority.json');
    const alternate = Buffer.concat([await readFile(installerPath), Buffer.from('\n// independently unauthorized alternate\n')]);
    const authority = JSON.parse(await readFile(authorityPath, 'utf8'));
    authority.source_sha256 = subject.sha256(alternate);
    await writeFile(installerPath, alternate, { mode: 0o600 });
    await writeFile(authorityPath, subject.canonicalJson(authority), { mode: 0o600 });
    const publisher1 = runActualCli(fixture.root, '--provision-mac-publisher1');
    assert.equal(publisher1.status, 1);
    await assert.rejects(lstat(path.join(fixture.authorityRoot, 'state', 'provision-mac-publisher1', 'attempt.json')));
    await assert.rejects(lstat(path.join(fixture.root, 'publisher1-installer-base', fixture.context.authority.commit,
      fixture.context.generations.controller)));
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round5 actual main rejects a mismatched canonical bootstrap request before installer compilation, claim, or tree', async () => {
  const fixture = await createActualCliFixture('publisher1');
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
    assert.equal(runActualCli(fixture.root, '--receive-vps-pass').status, 0);
    const requestPath = path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-bootstrap.request.json');
    const request = JSON.parse((await readFile(requestPath)).toString('utf8'));
    request.handoff.materializer_authority.request_identity_sha256 = '0'.repeat(64);
    await rm(requestPath);
    await writeOwnerOnlyFixture(requestPath, subject.canonicalJson(request));
    const result = runActualCli(fixture.root, '--provision-mac-publisher1');
    assert.equal(result.status, 1);
    await assert.rejects(lstat(path.join(fixture.root, 'fixed-bin', 'provision-mac-publisher1.ran')));
    await assert.rejects(lstat(path.join(fixture.authorityRoot, 'state', 'provision-mac-publisher1', 'attempt.json')));
    await assert.rejects(lstat(path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-installer.compile-receipt.json')));
    await assert.rejects(lstat(path.join(fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
      `bootstrap-${fixture.context.authority.manifest_sha256}`)));
    await assert.rejects(lstat(path.join(fixture.root, 'publisher1-state-base', fixture.context.authority.commit,
      fixture.context.generations.controller, 'publisher1-bootstrap.claim.json')));
  } finally { await cleanupSyntheticFixture(fixture.root); }
});

test('round5 actual-main producer feeds its unchanged synthetic-root transaction to the installed frozen writer entrypoint', async () => {
  const fixture = await createActualCliFixture('frozen-writer-transaction', { frozenWriter: true });
  try {
    assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
    assert.equal(runActualCli(fixture.root, '--provision-vps-publisher0').status, 0);
    assert.equal(runActualCli(fixture.root, '--receive-vps-pass').status, 0);
    assert.equal(runActualCli(fixture.root, '--provision-mac-publisher1').status, 0);
    const requestPath = path.join(fixture.root, '.config', 'agentempp', 'ci3', 'publisher-input', fixture.context.authority.commit,
      'publisher1-transaction.request.json');
    const requestBytes = await readFile(requestPath);
    const request = JSON.parse(requestBytes.toString('utf8'));
    assert.deepEqual(Object.keys(request).sort(), [
      'attempt', 'authority_sha', 'controller_generation_id', 'destination_parent', 'entries', 'purpose', 'raw_values',
      'receiver_manifest_sha256', 'receiver_root', 'remote_generation_id', 'retry', 'schema_version', 'state_root',
    ]);
    assert.equal(request.destination_parent, path.join(fixture.root, 'publisher1-terminal-authority'));
    assert.equal(request.state_root, path.join(fixture.root, 'publisher1-terminal-state', fixture.context.authority.commit,
      fixture.context.generations.controller));
    const installedWriter = path.join(fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
      `bootstrap-${fixture.context.authority.manifest_sha256}`, 'runtime', 'ci3-terminal-anchor-writer');
    const created = spawnSync(installedWriter, ['--publisher1-transaction'], {
      input: requestBytes, encoding: 'utf8', timeout: 30_000, maxBuffer: 64 * 1024,
      env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
    });
    assert.equal(created.status, 0, created.stderr);
    assert.match(created.stdout, /^PUBLISHER1_TRANSACTION PASS status=CREATED effect_executions=1\n$/);
    assert.equal((await lstat(path.join(request.destination_parent, fixture.context.authority.commit))).isDirectory(), true);
    const exactExisting = spawnSync(installedWriter, ['--publisher1-transaction'], {
      input: requestBytes, encoding: 'utf8', timeout: 30_000, maxBuffer: 64 * 1024,
      env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
    });
    assert.equal(exactExisting.status, 0, exactExisting.stderr);
    assert.match(exactExisting.stdout, /^PUBLISHER1_TRANSACTION PASS status=EXISTS_VERIFIED effect_executions=0\n$/);
  } finally {
    await cleanupSyntheticFixture(fixture.root);
  }
});

test('round5 installed frozen writer rejects a producer request identity mismatch before claim or final tree', async () => {
  const prepared = await provisionFrozenWriterFixture('frozen-writer-request-identity');
  try {
    const mismatched = structuredClone(prepared.request);
    mismatched.entries[0].source_identity_sha256 = '0'.repeat(64);
    const result = invokeInstalledFrozenWriter(prepared.writer, subject.canonicalJson(mismatched));
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR PUBLISHER1_SOURCE_AUTHORITY\n$/);
    await assert.rejects(lstat(path.join(prepared.request.state_root, 'publisher1.claim.json')));
    await assert.rejects(lstat(path.join(prepared.request.destination_parent, prepared.fixture.context.authority.commit)));
  } finally {
    await cleanupSyntheticFixture(prepared.fixture.root);
  }
});

test('round5 installed frozen writer rejects a producer receiver-leaf replacement before claim or final tree', async () => {
  const prepared = await provisionFrozenWriterFixture('frozen-writer-leaf');
  try {
    const role = subject.PUBLISHER1_ROLES[0];
    const leaf = path.join(prepared.request.receiver_root, `${role}.payload`);
    const bytes = await readFile(leaf);
    await rm(leaf);
    await writeOwnerOnlyFixture(leaf, bytes);
    const result = invokeInstalledFrozenWriter(prepared.writer, prepared.requestBytes);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR PUBLISHER1_SOURCE_AUTHORITY\n$/);
    await assert.rejects(lstat(path.join(prepared.request.state_root, 'publisher1.claim.json')));
    await assert.rejects(lstat(path.join(prepared.request.destination_parent, prepared.fixture.context.authority.commit)));
  } finally {
    await cleanupSyntheticFixture(prepared.fixture.root);
  }
});

test('round5 installed frozen writer rejects a destination-parent race without an accepted final tree', async () => {
  const prepared = await provisionFrozenWriterFixture('frozen-writer-destination-race');
  try {
    const result = invokeInstalledFrozenWriter(prepared.writer, prepared.requestBytes, {
      CI3_SYNTHETIC_PUBLISHER1_SWAP_DESTINATION: '1',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR PUBLISHER1_DESTINATION_DRIFT\n$/);
    await assert.rejects(lstat(path.join(prepared.request.destination_parent, prepared.fixture.context.authority.commit)));
    await assert.rejects(lstat(path.join(prepared.request.state_root, 'publisher1.result.json')));
  } finally {
    await cleanupSyntheticFixture(prepared.fixture.root);
  }
});

test('round5 installed frozen writer recovers a promoted producer tree without a second effect', async () => {
  const prepared = await provisionFrozenWriterFixture('frozen-writer-recovery');
  try {
    const crashed = invokeInstalledFrozenWriter(prepared.writer, prepared.requestBytes, {
      CI3_SYNTHETIC_PUBLISHER1_CRASH_AFTER: 'PROMOTION',
    });
    assert.notEqual(crashed.status, 0);
    assert.match(crashed.stderr, /^ERROR SYNTHETIC_CRASH\n$/);
    const recovered = invokeInstalledFrozenWriter(prepared.writer, prepared.requestBytes);
    assert.equal(recovered.status, 0, recovered.stderr);
    assert.match(recovered.stdout, /^PUBLISHER1_TRANSACTION PASS status=EXISTS_RECOVERED effect_executions=0\n$/);
  } finally {
    await cleanupSyntheticFixture(prepared.fixture.root);
  }
});

for (const [label, mutationStage, mutate] of [
  ['issuer', 'AFTER_PUBLISHER0', async (fixture) => {
    const capturePath = path.join(fixture.sourceRoot, 'publisher0-output.capture.json');
    const captured = JSON.parse((await readFile(capturePath)).toString('utf8'));
    captured.issuer = subject.buildVpsIssuerAuthority({
      authoritySha: fixture.context.authority.commit,
      issuerGenerationId: `issuer-${'e'.repeat(64)}`,
      publicKey: generateKeyPairSync('ed25519').publicKey,
    });
    await rm(capturePath);
    await writeOwnerOnlyFixture(capturePath, subject.canonicalJson(captured));
  }],
  ['writer identity', 'BEFORE_PUBLISHER0', async (fixture) => {
    const file = path.join(fixture.sourceRoot, 'publisher1-input', 'writer.swift');
    await rm(file);
    await writeOwnerOnlyFixture(file, Buffer.from('untrusted-writer\n'));
  }],
  ['authority subject', 'BEFORE_PUBLISHER0', async (fixture) => {
    const file = path.join(fixture.sourceRoot, 'context.json');
    const context = JSON.parse((await readFile(file)).toString('utf8'));
    context.authority.subject_sha256 = '0'.repeat(64);
    await rm(file);
    await writeOwnerOnlyFixture(file, subject.canonicalJson(context));
  }],
]) {
  test(`round5 actual producer rejects a swapped ${label} before bootstrap claim or installed writer tree`, async () => {
    const fixture = await createActualCliFixture(`producer-${label.replaceAll(' ', '-')}`);
    try {
      assert.equal(runActualCli(fixture.root, '--prepare').status, 0);
      if (mutationStage === 'BEFORE_PUBLISHER0') await mutate(fixture);
      const publisher0 = runActualCli(fixture.root, '--provision-vps-publisher0');
      if (mutationStage === 'AFTER_PUBLISHER0') {
        assert.equal(publisher0.status, 0, publisher0.stderr);
        await mutate(fixture);
        const receive = runActualCli(fixture.root, '--receive-vps-pass');
        assert.equal(receive.status, 1);
        assert.equal((await lstat(path.join(
          fixture.authorityRoot, 'state', 'receive-vps-pass', 'attempt.json',
        ))).isFile(), true);
        await assert.rejects(lstat(path.join(fixture.authorityRoot, 'state', 'receive-vps-pass', 'result.json')));
      } else {
        assert.equal(publisher0.status, 1);
        await assert.rejects(lstat(path.join(fixture.authorityRoot, 'state', 'provision-vps-publisher0', 'attempt.json')));
      }
      await assert.rejects(lstat(path.join(fixture.sourceRoot, 'publisher1-produced', 'publisher1-bootstrap.request.json')));
      await assert.rejects(lstat(path.join(fixture.root, 'publisher1-install-base', fixture.context.authority.commit,
        `bootstrap-${fixture.context.authority.manifest_sha256}`)));
      await assert.rejects(lstat(path.join(fixture.root, 'publisher1-terminal-state', fixture.context.authority.commit,
        fixture.context.generations.controller, 'publisher1.claim.json')));
    } finally {
      await cleanupSyntheticFixture(fixture.root);
    }
  });
}

test('round2 dispatcher executes only the injected local preparation handler', async () => {
  let prepared = 0;
  const result = await subject.dispatchExternalPublisherMode('--prepare', {
    prepare: async () => { prepared += 1; return { state: 'PREPARED', raw_values: false }; },
  });
  assert.deepEqual(result, { state: 'PREPARED', raw_values: false });
  assert.equal(prepared, 1);
});

test('round2 bounded fixed subprocess recovers exact-existing without spawning', async () => {
  let spawns = 0;
  const result = await subject.runBoundedFixedSubprocess({
    executable: process.execPath, argv: ['--version'], expectedExisting: async () => true,
    persistAttempt: async () => { throw new Error('must not persist'); },
    spawn: () => { spawns += 1; throw new Error('must not spawn'); },
  });
  assert.deepEqual(result, { state: 'EXISTS_VERIFIED', effect_executions: 0, raw_values: false });
  assert.equal(spawns, 0);
});

test('round3 outer ledger recovers attempt-present result-absent only from an exact settled effect without respawn retry refetch prompt or cleanup', async () => {
  let spawns = 0;
  let recoveredResults = 0;
  let observations = 0;
  const result = await subject.runBoundedFixedSubprocess({
    executable: process.execPath, argv: ['--fixed-synthetic-command'],
    expectedExisting: async () => false,
    attemptExisting: async () => true,
    observeSettled: async () => { observations += 1; return 'SETTLED_EXACT'; },
    persistRecoveredResult: async () => { recoveredResults += 1; return true; },
    persistAttempt: async () => { throw new Error('must not consume another attempt'); },
    spawn: () => { spawns += 1; throw new Error('must not respawn'); },
  });
  assert.deepEqual(result, { state: 'RECOVERED_VERIFIED', effect_executions: 0, raw_values: false });
  assert.equal(observations, 1);
  assert.equal(recoveredResults, 1);
  assert.equal(spawns, 0);
  for (const settled of ['PARTIAL', 'DIVERGENT', 'ABSENT']) {
    await rejectCode('STOP_PRE_AUTHORITY', () => subject.runBoundedFixedSubprocess({
      executable: process.execPath, argv: ['--fixed-synthetic-command'],
      expectedExisting: async () => false, attemptExisting: async () => true,
      observeSettled: async () => settled,
      persistRecoveredResult: async () => { throw new Error('must not publish a partial recovery'); },
      persistAttempt: async () => { throw new Error('must not retry'); },
      spawn: () => { spawns += 1; throw new Error('must not respawn'); },
    }));
  }
  assert.equal(spawns, 0);
});

test('round3 missing fixed executable stops before consuming the one-shot attempt', async () => {
  let attempts = 0;
  let spawns = 0;
  await rejectCode('STOP_PRE_AUTHORITY', () => subject.runBoundedFixedSubprocess({
    executable: '/private/ci3-round3-deliberately-absent', argv: [],
    expectedExisting: async () => false,
    persistAttempt: async () => { attempts += 1; return true; },
    spawn: () => { spawns += 1; throw new Error('missing executable must not reach spawn'); },
  }));
  assert.equal(attempts, 0);
  assert.equal(spawns, 0);
});

test('round2 bounded fixed subprocess uses closed environment and persists once before the fake fixed executable', async () => {
  let persisted = 0;
  let options;
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.kill = () => true;
  const result = await subject.runBoundedFixedSubprocess({
    executable: process.execPath, argv: ['--fixed-synthetic-command'], expectedExisting: async () => false,
    persistAttempt: async () => { persisted += 1; return true; },
    spawn: (_executable, _argv, received) => {
      options = received;
      queueMicrotask(() => child.emit('close', 0));
      return child;
    },
  });
  assert.equal(persisted, 1);
  assert.deepEqual(options.env, subject.CLOSED_ENVIRONMENT);
  assert.equal(options.shell, false);
  assert.deepEqual(result, { state: 'CREATED', effect_executions: 1, stdout_bytes: 0, stderr_bytes: 0, raw_values: false });
});

test('successor bounded P0 subprocess captures exact stdout bytes instead of discarding transport', async () => {
  const payload = Buffer.from('{"purpose":"authenticated-publisher0-output"}\n');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.kill = () => true;
  const result = await subject.runBoundedFixedSubprocess({
    executable: process.execPath, argv: ['--fixed-synthetic-p0'], captureStdout: true,
    expectedExisting: async () => false, persistAttempt: async () => true,
    spawn: () => {
      queueMicrotask(() => {
        child.stdout.emit('data', payload.subarray(0, 9));
        child.stdout.emit('data', payload.subarray(9));
        child.emit('close', 0);
      });
      return child;
    },
  });
  assert.equal(result.state, 'CREATED');
  assert.equal(result.stdout_bytes, payload.length);
  assert.deepEqual(result.stdout, payload);
  assert.equal(result.stdout_sha256, subject.sha256(payload));
  assert.equal(result.raw_values, false);
});

test('round4 bounded P0 subprocess durably journals authenticated stdout before reporting remote settlement', async () => {
  const root = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-round4-p0-journal-')));
  const journalPath = path.join(root, 'publisher0-output.capture.journal');
  const payload = Buffer.from('{"purpose":"authenticated-publisher0-output","raw_values":false}\n');
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.kill = () => true;
  try {
    const result = await subject.runBoundedFixedSubprocess({
      executable: process.execPath, argv: ['--fixed-synthetic-p0'], captureStdout: true,
      stdoutJournalPath: journalPath,
      expectedExisting: async () => false, persistAttempt: async () => true,
      spawn: () => {
        queueMicrotask(() => {
          child.stdout.emit('data', payload.subarray(0, 17));
          child.stdout.emit('data', payload.subarray(17));
          child.emit('close', 0);
        });
        return child;
      },
    });
    assert.equal(result.state, 'CREATED');
    assert.deepEqual(await readFile(journalPath), payload);
    assert.equal((await lstat(journalPath)).mode & 0o777, 0o600);
  } finally {
    await cleanupSyntheticFixture(root);
  }
});

test('round2 bounded fixed subprocess terminates the fake child after timeout and never retries', async () => {
  let persisted = 0;
  const signals = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.kill = (signal) => {
    signals.push(signal);
    if (signal === 'SIGTERM') queueMicrotask(() => { child.signalCode = signal; child.emit('close', null); });
    return true;
  };
  await rejectCode('STOP_PRE_AUTHORITY', () => subject.runBoundedFixedSubprocess({
    executable: process.execPath, argv: ['--fixed-synthetic-command'], expectedExisting: async () => false,
    persistAttempt: async () => { persisted += 1; return true; }, spawn: () => child, timeoutMs: 5,
  }));
  assert.equal(persisted, 1);
  assert.deepEqual(signals, ['SIGTERM']);
});

test('round2 missing external authority stops all five operational adapters before any fake spawn', () => {
  let spawns = 0;
  assert.throws(() => subject.createFixedOperationalHandlers({
    authorityReady: false, invocations: {}, spawn: () => { spawns += 1; throw new Error('must not spawn'); },
  }), (error) => error?.code === 'STOP_PRE_AUTHORITY');
  assert.equal(spawns, 0);
});

test('round2 all five fixed operational handlers run only their fixed bounded adapter', async () => {
  let persisted = 0;
  let spawns = 0;
  const invocation = () => ({
    executable: process.execPath, argv: ['--fixed-synthetic-command'],
    expectedExisting: async () => false, persistAttempt: async () => { persisted += 1; return true; },
  });
  const handlers = subject.createFixedOperationalHandlers({
    authorityReady: true,
    invocations: Object.fromEntries(['prepare', 'provisionPublisher0', 'receivePublisher0Pass', 'provisionPublisher1', 'verifyChain'].map((name) => [name, invocation()])),
    spawn: () => {
      spawns += 1;
      const child = new EventEmitter();
      child.stdout = new EventEmitter(); child.stderr = new EventEmitter(); child.exitCode = null; child.signalCode = null;
      child.kill = () => true;
      queueMicrotask(() => child.emit('close', 0));
      return child;
    },
  });
  for (const mode of ['--prepare', '--provision-vps-publisher0', '--receive-vps-pass', '--provision-mac-publisher1', '--verify-chain']) {
    const result = await subject.dispatchExternalPublisherMode(mode, handlers);
    assert.equal(result.state, 'CREATED');
    assert.equal(result.raw_values, false);
  }
  assert.equal(persisted, 5);
  assert.equal(spawns, 5);
});

test('round2 canonical Node-to-Swift handoff binds preserved Gate0, pass, human receipt and sixteen leaves', () => {
  const bindings = syntheticBindings();
  const context = syntheticContext();
  context.authority.commit = bindings.MAC_EXECUTOR_AUTHORITY_SHA;
  context.authority.parent = bindings.MAC_EXECUTOR_AUTHORITY_PARENT;
  context.authority.tree = bindings.MAC_EXECUTOR_AUTHORITY_TREE;
  context.authority.subject_sha256 = subject.sha256(Buffer.from(bindings.MAC_EXECUTOR_AUTHORITY_SUBJECT));
  const receiver = syntheticReceiver();
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const issuer = subject.buildVpsIssuerAuthority({
    authoritySha: context.authority.commit,
    issuerGenerationId: `issuer-${'9'.repeat(64)}`,
    publicKey,
  });
  const manifest = subject.buildPublisherInputManifest({
    context,
    entries: subject.TRANSPORT_ROLES.map((role, index) => ({
      role, path_sha256: String((index % 8) + 1).repeat(64), sha256: String(((index + 2) % 8) + 1).repeat(64),
    })),
  });
  const pass = subject.signVpsPass({
    unsigned: subject.buildUnsignedVpsPass({
      context, issuer, publisherInputManifestSha256: subject.sha256(subject.canonicalJson(manifest)), transferPayloadSha256: manifest.transfer_payload_sha256,
    }),
    issuer,
    privateKey,
  });
  const materializer = subject.buildPublisher1MaterializerAuthority({
    context,
    requestPath: '/private/var/folders/synthetic/transaction.request.json',
    requestSha256: 'a'.repeat(64),
    requestObservation: { ...syntheticObservation('request', '/private/var/folders/synthetic', 30), path: '/private/var/folders/synthetic/transaction.request.json', path_sha256: subject.sha256(Buffer.from('/private/var/folders/synthetic/transaction.request.json')) },
    receiverRoot: receiver.root, receiverRootIdentitySha256: 'b'.repeat(64), receiverLeaves: Object.values(receiver.observations),
    issuerAuthoritySha256: subject.sha256(subject.canonicalJson(issuer)), materializerSha256: 'd'.repeat(64), writerSourceSha256: context.authority.components.writer.sha256,
  });
  const receiverLeaves = Object.values(receiver.observations);
  const preauthorizationLeaves = receiverLeaves.filter(({ role }) => role !== 'human-authorization');
  const installerProvenance = {
    git_path: 'scripts/ci3/ci3-publisher1-bootstrap-installer.swift', git_blob_oid: 'c'.repeat(40),
    source_sha256: 'd'.repeat(64), authority_manifest_sha256: context.authority.manifest_sha256,
    compile_authority_sha256: 'e'.repeat(64), expected_binary_sha256: 'f'.repeat(64),
  };
  const promptSha256 = '1'.repeat(64);
  const humanAuthorizationRequest = subject.buildHumanAuthorizationRequest({
    context, issuer, manifest, pass, receiverRoot: receiver.root, receiverRootIdentitySha256: 'b'.repeat(64),
    receiverLeaves: preauthorizationLeaves, installerProvenance, promptSha256,
  });
  const authorizationRequestBytes = subject.canonicalJson(humanAuthorizationRequest);
  const authorizationRequestPath = '/private/var/folders/synthetic/publisher1-human-authorization.request.json';
  const authorizationRequestMetadata = {
    uid: 501, gid: 20, mode: 0o600, nlink: 1, size: authorizationRequestBytes.length,
    mtime_ns: '1700000000000000000', dev: '800', ino: '801',
  };
  const humanAuthorizationRequestObservation = {
    role: 'human-authorization-request', path: authorizationRequestPath,
    path_sha256: subject.sha256(Buffer.from(authorizationRequestPath)),
    sha256: subject.sha256(authorizationRequestBytes), ...authorizationRequestMetadata,
    identity_sha256: subject.physicalIdentitySha256(authorizationRequestMetadata),
  };
  const humanAuthorization = subject.buildHumanAuthorizationReceipt({
    context, issuer, manifest, pass, authorizationRequest: humanAuthorizationRequest,
    authorizationRequestObservation: humanAuthorizationRequestObservation,
    receiverRoot: receiver.root, receiverRootIdentitySha256: 'b'.repeat(64),
    receiverLeaves: preauthorizationLeaves, installerProvenance, promptSha256,
    confirmation: { authorized_uid: 501, authorized_gid: 20, prompt_budget: 1, confirmation_sha256: '2'.repeat(64) },
  });
  const handoff = subject.buildPublisher1BootstrapHandoff({
    bindings,
    context,
    gate0Receipt: cliGate0(bindings, context),
    issuer,
    pass,
    transportManifest: manifest,
    humanAuthorization, humanAuthorizationRequest, humanAuthorizationRequestObservation,
    installerProvenance, promptSha256,
    materializerAuthority: materializer,
    receiverRoot: receiver.root,
    receiverRootIdentitySha256: 'b'.repeat(64),
    receiverLeaves,
  });
  assert.equal(handoff.purpose, 'CI3_PUBLISHER1_BOOTSTRAP_HANDOFF_V2');
  assert.equal(handoff.receiver_leaves.length, 16);
  assert.equal(subject.validatePublisher1BootstrapHandoff(JSON.parse(subject.canonicalJson(handoff).toString('utf8')), { bindings, context, receiverRoot: receiver.root, receiverRootIdentitySha256: 'b'.repeat(64), receiverLeaves }), true);
});

const SEMANTIC_SAFE_CHAIN_STAGES = Object.freeze([
  'SUCCESSOR_AUTHORITY_PUBLISHED',
  'EXACT_BLOBS_GREEN',
  'GATE0_PASS',
  'PUBLISHER0_PASS',
  'ISSUER_AND_SIGNED_PASS_READY',
  'PUBLISHER_MANIFEST_TRANSPORTED',
  'OWNER_ONLY_MAC_CAPTURED',
  'RECEIVER_READY',
  'REQUEST_READY',
  'HUMAN_AUTHORIZED',
  'FINAL_PHYSICAL_IDENTITIES',
  'SEMANTIC_PREFLIGHT_PASS',
  'IMMUTABLE_INSTALLER_PHASE_A_PASS',
  'PUBLISHER1_PHASE_B_PASS',
  'PUBLISHER1_READBACK_PASS',
  'OPERATION_AUTHORITY_PUBLISHED',
  'CONTROLLER_AUTHORITY_READBACK',
  'SETTLED',
]);

test('successor state machine accepts the exact semantic-safe chain once in order', () => {
  let state = subject.createSemanticSafePublisherChainState();
  for (const stage of SEMANTIC_SAFE_CHAIN_STAGES) {
    state = subject.advanceSemanticSafePublisherChainState(state, stage);
  }
  assert.deepEqual(state, {
    schema_version: 2,
    purpose: 'CI3_SEMANTIC_SAFE_PUBLISHER_CHAIN_V2',
    completed: SEMANTIC_SAFE_CHAIN_STAGES,
    attempt: 1,
    retry: false,
    raw_values: false,
  });
});

for (const [nextIndex, expectedStage] of SEMANTIC_SAFE_CHAIN_STAGES.entries()) {
  for (const rejectedStage of SEMANTIC_SAFE_CHAIN_STAGES.filter((stage) => stage !== expectedStage).slice(0, 3)) {
    test(`successor order rejects ${rejectedStage} while the sole next stage is ${expectedStage}`, () => {
      const state = {
        schema_version: 2,
        purpose: 'CI3_SEMANTIC_SAFE_PUBLISHER_CHAIN_V2',
        completed: SEMANTIC_SAFE_CHAIN_STAGES.slice(0, nextIndex),
        attempt: 1,
        retry: false,
        raw_values: false,
      };
      assert.throws(
        () => subject.advanceSemanticSafePublisherChainState(state, rejectedStage),
        (error) => error?.code === 'PUBLISHER_CHAIN_ORDER',
      );
      assert.deepEqual(state.completed, SEMANTIC_SAFE_CHAIN_STAGES.slice(0, nextIndex));
    });
  }
}

test('successor state machine rejects any transition after settlement', () => {
  const state = {
    schema_version: 2,
    purpose: 'CI3_SEMANTIC_SAFE_PUBLISHER_CHAIN_V2',
    completed: [...SEMANTIC_SAFE_CHAIN_STAGES],
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  assert.throws(
    () => subject.advanceSemanticSafePublisherChainState(state, 'SETTLED'),
    (error) => error?.code === 'PUBLISHER_CHAIN_ORDER',
  );
});
