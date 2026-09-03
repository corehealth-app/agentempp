import CryptoKit
import Darwin
import Foundation

@_silgen_name("_dyld_get_image_name")
private func dyldImageName(_ index: UInt32) -> UnsafePointer<CChar>?

@_silgen_name("flock")
private func ci3Flock(_ descriptor: Int32, _ operation: Int32) -> Int32

private enum BootstrapError: Error { case rejected }

private func reject() throws -> Never { throw BootstrapError.rejected }

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func exactKeys(_ object: [String: Any], _ keys: [String]) throws {
    guard Set(object.keys) == Set(keys) else { try reject() }
}

private func string(_ value: Any?) throws -> String {
    guard let value = value as? String else { try reject() }
    return value
}

private func integer(_ value: Any?) throws -> Int {
    guard let value = value as? NSNumber else { try reject() }
    guard CFGetTypeID(value) != CFBooleanGetTypeID() else { try reject() }
    let encoding = String(cString: value.objCType)
    guard ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(encoding) else { try reject() }
    let parsed = value.int64Value
    guard Int64(Int(parsed)) == parsed else { try reject() }
    return Int(parsed)
}

private func boolean(_ value: Any?) throws -> Bool {
    guard let value = value as? Bool else { try reject() }
    return value
}

private func object(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else { try reject() }
    return value
}

private func array(_ value: Any?) throws -> [[String: Any]] {
    guard let value = value as? [[String: Any]] else { try reject() }
    return value
}

private func isHex(_ value: String, _ count: Int = 64) -> Bool {
    value.count == count && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
}

private func isGeneration(_ value: String) -> Bool {
    let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    return parts.count == 2 && !parts[0].isEmpty && isHex(String(parts[1]))
}

private let nodeSafeMaximum = 9_007_199_254_740_991

private func canonicalDecimal(_ value: String, maximum: UInt64) throws -> UInt64 {
    guard value == "0" || (!value.isEmpty && value.first != "0" && value.allSatisfy({ $0.isNumber })) else { try reject() }
    guard let parsed = UInt64(value), parsed <= maximum else { try reject() }
    return parsed
}

private func safeAbsolutePath(_ value: String) -> Bool {
    value.hasPrefix("/") && !value.contains("\u{0}") && !value.contains("\n")
        && !value.contains("\r") && !value.contains("/../")
}

private struct Physical {
    let uid: Int
    let gid: Int
    let mode: Int
    let nlink: Int
    let size: Int
    let mtimeNS: String
    let dev: String
    let ino: String

    func identity() -> String {
        sha256(Data("uid=\(uid);gid=\(gid);mode=\(mode);nlink=\(nlink);size=\(size);mtime=\(mtimeNS);dev=\(dev);ino=\(ino)".utf8))
    }
}

private func productionMetadataRequired() -> Bool {
#if CI3_SYNTHETIC_TEST
    return ProcessInfo.processInfo.environment["CI3_SYNTHETIC_PRODUCTION_METADATA"] == "1"
#else
    return true
#endif
}

private func expectedPublishedUID() -> uid_t {
#if CI3_SYNTHETIC_TEST
    return getuid()
#else
    return 0
#endif
}

private func expectedPublishedGID() -> gid_t {
#if CI3_SYNTHETIC_TEST
    return getgid()
#else
    return 0
#endif
}

private func physical(_ value: stat) throws -> Physical {
    let seconds = Int64(value.st_mtimespec.tv_sec)
    let nanoseconds = Int64(value.st_mtimespec.tv_nsec)
    guard seconds >= 0, nanoseconds >= 0 else { try reject() }
    return Physical(
        uid: Int(value.st_uid), gid: Int(value.st_gid), mode: Int(value.st_mode & 0o777),
        nlink: Int(value.st_nlink), size: Int(value.st_size),
        mtimeNS: String(seconds * 1_000_000_000 + nanoseconds),
        dev: String(UInt64(value.st_dev)), ino: String(UInt64(value.st_ino))
    )
}

private func samePinnedDirectory(_ left: Physical, _ right: Physical) -> Bool {
    left.uid == right.uid && left.gid == right.gid && left.mode == right.mode
        && left.dev == right.dev && left.ino == right.ino
}

private func namedDirectoryStillMatches(_ absolutePath: String, _ expected: Physical) throws -> Bool {
    let chain = try openDirectoryChain(absolutePath, create: false)
    defer { for descriptor in chain.reversed() { Darwin.close(descriptor) } }
    return samePinnedDirectory(try physical(fstatValue(chain.last!)), expected)
}

private func fstatValue(_ descriptor: Int32) throws -> stat {
    var value = stat()
    guard Darwin.fstat(descriptor, &value) == 0 else { try reject() }
    return value
}

private func readDescriptor(_ descriptor: Int32, limit: Int = 16 * 1024 * 1024) throws -> Data {
    guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else { try reject() }
    var output = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        guard count >= 0 else { try reject() }
        if count == 0 { break }
        output.append(buffer, count: count)
        guard output.count <= limit else { try reject() }
    }
    return output
}

private func openDirectoryChain(_ path: String, create: Bool) throws -> [Int32] {
    guard safeAbsolutePath(path) else { try reject() }
    let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard root >= 0 else { try reject() }
    var descriptors = [root]
    var current = root
    do {
        for component in path.split(separator: "/").map(String.init) {
            if create {
                let created = component.withCString { Darwin.mkdirat(current, $0, 0o700) }
                guard created == 0 || errno == EEXIST else { try reject() }
            }
            let next = component.withCString { Darwin.openat(current, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
            guard next >= 0 else { try reject() }
            let observed = try fstatValue(next)
            guard (observed.st_mode & S_IFMT) == S_IFDIR else { Darwin.close(next); try reject() }
#if CI3_SYNTHETIC_TEST
            guard (observed.st_mode & 0o022) == 0 || (component == "tmp" && (observed.st_mode & S_ISVTX) != 0) else { Darwin.close(next); try reject() }
#else
            guard (observed.st_mode & 0o022) == 0 else { Darwin.close(next); try reject() }
#endif
            descriptors.append(next)
            current = next
        }
        return descriptors
    } catch {
        for descriptor in descriptors.reversed() { Darwin.close(descriptor) }
        throw error
    }
}

private func openPinnedFile(_ absolutePath: String) throws -> (parent: Int32, leaf: String, descriptor: Int32, before: Physical) {
    guard safeAbsolutePath(absolutePath) else { try reject() }
    let parentPath = (absolutePath as NSString).deletingLastPathComponent
    let leaf = (absolutePath as NSString).lastPathComponent
    guard !leaf.isEmpty, leaf != ".", leaf != ".." else { try reject() }
    let chain = try openDirectoryChain(parentPath, create: false)
    let parent = chain.last!
    for descriptor in chain.dropLast().reversed() { Darwin.close(descriptor) }
    let descriptor = leaf.withCString { Darwin.openat(parent, $0, O_RDONLY | O_NOFOLLOW) }
    guard descriptor >= 0 else { Darwin.close(parent); try reject() }
    let observed = try fstatValue(descriptor)
    let before = try physical(observed)
    guard (observed.st_mode & S_IFMT) == S_IFREG, before.nlink == 1 else { Darwin.close(descriptor); Darwin.close(parent); try reject() }
    return (parent, leaf, descriptor, before)
}

private func writeExclusiveAt(_ parent: Int32, _ leaf: String, _ data: Data, _ mode: mode_t, rootOwned: Bool = true) throws {
    guard !leaf.isEmpty, !leaf.contains("/"), leaf != ".", leaf != ".." else { try reject() }
    let descriptor = leaf.withCString { Darwin.openat(parent, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode) }
    guard descriptor >= 0 else { try reject() }
    defer { Darwin.close(descriptor) }
    var offset = 0
    let complete = data.withUnsafeBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return data.isEmpty }
        while offset < data.count {
            let written = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
            if written <= 0 { return false }
            offset += written
        }
        return true
    }
    #if !CI3_SYNTHETIC_TEST
    if rootOwned { guard Darwin.fchown(descriptor, 0, 0) == 0 else { try reject() } }
    #endif
    guard complete, Darwin.fchmod(descriptor, mode) == 0, Darwin.fsync(descriptor) == 0, Darwin.fsync(parent) == 0 else { try reject() }
}

private func openDirectoryAt(_ parent: Int32, _ leaf: String, create: Bool) throws -> Int32 {
    guard !leaf.isEmpty, !leaf.contains("/"), leaf != ".", leaf != ".." else { try reject() }
    if create {
        let created = leaf.withCString { Darwin.mkdirat(parent, $0, 0o700) }
        guard created == 0 || errno == EEXIST else { try reject() }
    }
    let descriptor = leaf.withCString { Darwin.openat(parent, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
    guard descriptor >= 0 else { try reject() }
    let observed = try fstatValue(descriptor)
    guard (observed.st_mode & S_IFMT) == S_IFDIR else { Darwin.close(descriptor); try reject() }
    return descriptor
}

private func readExistingAt(_ parent: Int32, _ leaf: String) throws -> Data? {
    guard !leaf.isEmpty, !leaf.contains("/"), leaf != ".", leaf != ".." else { try reject() }
    let descriptor = leaf.withCString { Darwin.openat(parent, $0, O_RDONLY | O_NOFOLLOW) }
    if descriptor < 0 {
        guard errno == ENOENT else { try reject() }
        return nil
    }
    defer { Darwin.close(descriptor) }
    let before = try physical(try fstatValue(descriptor))
    guard before.nlink == 1 else { try reject() }
    let bytes = try readDescriptor(descriptor)
    let after = try physical(try fstatValue(descriptor))
    var relative = stat()
    guard after.identity() == before.identity(),
          leaf.withCString({ Darwin.fstatat(parent, $0, &relative, AT_SYMLINK_NOFOLLOW) }) == 0,
          (relative.st_mode & S_IFMT) == S_IFREG,
          (try physical(relative)).identity() == before.identity() else { try reject() }
    return bytes
}

private func freezeOwnedDescriptor(_ descriptor: Int32, _ mode: mode_t) throws {
    if productionMetadataRequired() {
        let existing = try fstatValue(descriptor)
        if (existing.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
            guard existing.st_uid == expectedPublishedUID(), existing.st_gid == expectedPublishedGID(),
                  (existing.st_mode & 0o777) == mode else { try reject() }
        } else {
            guard Darwin.fchown(descriptor, expectedPublishedUID(), expectedPublishedGID()) == 0,
                  Darwin.fchmod(descriptor, mode) == 0,
                  Darwin.fchflags(descriptor, UInt32(UF_IMMUTABLE)) == 0 else { try reject() }
        }
    }
    guard Darwin.fsync(descriptor) == 0 else { try reject() }
}

private func freezeLeafAt(_ parent: Int32, _ leaf: String, _ mode: mode_t) throws {
    let descriptor = leaf.withCString { Darwin.openat(parent, $0, O_RDONLY | O_NOFOLLOW) }
    guard descriptor >= 0 else { try reject() }
    defer { Darwin.close(descriptor) }
    let before = try physical(fstatValue(descriptor))
    guard before.nlink == 1, before.mode == Int(mode) else { try reject() }
    try freezeOwnedDescriptor(descriptor, mode)
    guard Darwin.fsync(parent) == 0 else { try reject() }
}

private func requireExactDirectoryChildren(_ descriptor: Int32, _ expected: [String]) throws {
    let duplicate = Darwin.dup(descriptor)
    guard duplicate >= 0, let stream = Darwin.fdopendir(duplicate) else {
        if duplicate >= 0 { Darwin.close(duplicate) }
        try reject()
    }
    defer { Darwin.closedir(stream) }
    var names: [String] = []
    while let entry = Darwin.readdir(stream) {
        let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
        }
        if name != "." && name != ".." { names.append(name) }
    }
    guard names.count == expected.count, Set(names) == Set(expected) else { try reject() }
}

private func statAt(_ parent: Int32, _ leaf: String) throws -> stat? {
    guard !leaf.isEmpty, !leaf.contains("/"), leaf != ".", leaf != ".." else { try reject() }
    var observed = stat()
    let status = leaf.withCString { Darwin.fstatat(parent, $0, &observed, AT_SYMLINK_NOFOLLOW) }
    if status == 0 { return observed }
    guard errno == ENOENT else { try reject() }
    return nil
}

private struct Entry {
    let role: String
    let sourcePath: String
    let sourceSHA: String
    let relative: String
    let mode: mode_t
    let bytes: Data
    let physical: Physical
}

private let expectedRoles = [
    "materializer-authority", "issuer-receipt", "writer-binary",
    "node-runtime", "controller", "launcher-runtime", "launcher-bootstrap-authority",
    "launch-attestation", "authority-manifest",
]
private let expectedDestinations = [
    "publisher1-materializer.authority.json",
    "vps-issuer-authority.receipt.json",
    "runtime/ci3-terminal-anchor-writer",
    "runtime/node",
    "runtime/ci3-bridge-controller.mjs",
    "runtime/ci3-bridge-launcher.zsh",
    "runtime/launcher-bootstrap.authority.v1",
    "runtime/launch-attestation.json",
    "runtime/authority-manifest.v1",
]
private let expectedModes: [mode_t] = [0o444, 0o444, 0o555, 0o555, 0o555, 0o555, 0o444, 0o444, 0o444]

private func validateEntry(_ record: [String: Any], index: Int) throws -> Entry {
    try exactKeys(record, [
        "role", "source_path", "source_path_sha256", "source_sha256", "source_uid", "source_gid",
        "source_mode", "source_nlink", "source_size", "source_mtime_ns", "source_dev", "source_ino",
        "source_identity_sha256", "destination_relative_path", "mode",
    ])
    let role = try string(record["role"])
    let source = try string(record["source_path"])
    let sourcePathSHA = try string(record["source_path_sha256"])
    let sourceSHA = try string(record["source_sha256"])
    let sourceMtime = try string(record["source_mtime_ns"])
    let sourceDev = try string(record["source_dev"])
    let sourceIno = try string(record["source_ino"])
    let sourceIdentity = try string(record["source_identity_sha256"])
    let relative = try string(record["destination_relative_path"])
    let destinationMode = try integer(record["mode"])
    guard role == expectedRoles[index], safeAbsolutePath(source), sourcePathSHA == sha256(Data(source.utf8)),
          isHex(sourceSHA), isHex(sourceIdentity), !sourceMtime.isEmpty, !sourceDev.isEmpty, !sourceIno.isEmpty,
          relative == expectedDestinations[index], destinationMode == Int(expectedModes[index]), !relative.hasPrefix("/"),
          !relative.contains("..") else { try reject() }
    let pinned = try openPinnedFile(source)
    defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
    let sourceMetadata = pinned.before
    let sourceUID = try integer(record["source_uid"])
    let sourceGID = try integer(record["source_gid"])
    let sourceMode = try integer(record["source_mode"])
    let sourceNlink = try integer(record["source_nlink"])
    let sourceSize = try integer(record["source_size"])
    guard sourceMetadata.uid == sourceUID, sourceMetadata.gid == sourceGID,
          sourceMetadata.mode == sourceMode, sourceMetadata.nlink == sourceNlink,
          sourceMetadata.size == sourceSize, sourceMetadata.mtimeNS == sourceMtime,
          sourceMetadata.dev == sourceDev, sourceMetadata.ino == sourceIno, sourceMetadata.identity() == sourceIdentity else { try reject() }
    let bytes = try readDescriptor(pinned.descriptor)
    let after = try physical(try fstatValue(pinned.descriptor))
    var relativeStat = stat()
    guard sourceSHA == sha256(bytes), after.identity() == sourceMetadata.identity(),
          pinned.leaf.withCString({ Darwin.fstatat(pinned.parent, $0, &relativeStat, AT_SYMLINK_NOFOLLOW) }) == 0,
          (try physical(relativeStat)).identity() == sourceMetadata.identity() else { try reject() }
    return Entry(role: role, sourcePath: source, sourceSHA: sourceSHA, relative: relative, mode: expectedModes[index], bytes: bytes, physical: sourceMetadata)
}

private func validateHandoff(_ handoff: [String: Any], authority: String, generation: String, entries: [Entry]) throws {
    try exactKeys(handoff, [
        "schema_version", "purpose", "authority_sha", "remote_generation_id", "controller_generation_id",
        "authority_projection", "gate0_receipt", "issuer", "pass", "transport_manifest",
        "human_authorization_request", "human_authorization_request_observation", "human_authorization",
        "installer_provenance", "prompt_sha256", "materializer_authority",
        "receiver_root_path_sha256", "receiver_root_identity_sha256", "receiver_leaves", "attempt", "retry", "raw_values",
    ])
    let remote = try string(handoff["remote_generation_id"])
    let issuer = try object(handoff["issuer"])
    let projection = try object(handoff["authority_projection"])
    let pass = try object(handoff["pass"])
    let manifest = try object(handoff["transport_manifest"])
    let humanRequest = try object(handoff["human_authorization_request"])
    let humanRequestObservation = try object(handoff["human_authorization_request_observation"])
    let human = try object(handoff["human_authorization"])
    let installerProvenance = try object(handoff["installer_provenance"])
    let materializer = try object(handoff["materializer_authority"])
    let gate0 = try object(handoff["gate0_receipt"])
    let leaves = try array(handoff["receiver_leaves"])
    guard try integer(handoff["schema_version"]) == 2,
          try string(handoff["purpose"]) == "CI3_PUBLISHER1_BOOTSTRAP_HANDOFF_V2",
          try string(handoff["authority_sha"]) == authority, isGeneration(remote),
          try string(handoff["controller_generation_id"]) == generation,
          isHex(try string(handoff["receiver_root_path_sha256"])), isHex(try string(handoff["receiver_root_identity_sha256"])),
          try integer(handoff["attempt"]) == 1, try boolean(handoff["retry"]) == false, try boolean(handoff["raw_values"]) == false,
          leaves.count == receiverRoles.count else { try reject() }
    try exactKeys(projection, [
        "authority_sha", "authority_parent", "authority_tree", "authority_subject_sha256", "authority_manifest_sha256",
        "operation_authority_sha256", "node_candidate_sha256", "collector_contracts_sha256",
        "remote_generation_id", "controller_generation_id",
    ])
    guard try string(projection["authority_sha"]) == authority,
          try string(projection["remote_generation_id"]) == remote,
          try string(projection["controller_generation_id"]) == generation,
          isHex(try string(projection["authority_parent"]), 40), isHex(try string(projection["authority_tree"]), 40),
          isHex(try string(projection["authority_subject_sha256"])), isHex(try string(projection["authority_manifest_sha256"])),
          isHex(try string(projection["operation_authority_sha256"])), isHex(try string(projection["node_candidate_sha256"])),
          isHex(try string(projection["collector_contracts_sha256"])) else { try reject() }
    let projectionHash = sha256(try canonicalJSON(projection))
    try exactKeys(gate0, [
        "schema_version", "purpose", "authority_sha", "authority_manifest_sha256", "launcher_sha256",
        "exit_code", "stdout_bytes", "stderr_bytes", "status", "raw_values",
    ])
    guard try integer(gate0["schema_version"]) == 2,
          try string(gate0["purpose"]) == "CI3_SEMANTIC_SAFE_MAC_GATE0_V2",
          try string(gate0["authority_sha"]) == authority,
          try string(gate0["authority_manifest_sha256"]) == string(projection["authority_manifest_sha256"]),
          isHex(try string(gate0["launcher_sha256"])),
          try string(gate0["status"]) == "PASS", try integer(gate0["exit_code"]) == 0,
          try integer(gate0["stdout_bytes"]) == 0, try integer(gate0["stderr_bytes"]) == 0,
          try boolean(gate0["raw_values"]) == false else { try reject() }
    let gate0Manifest = try string(gate0["authority_manifest_sha256"])
    try exactKeys(issuer, [
        "schema_version", "purpose", "authority_sha", "issuer_generation_id", "public_key_algorithm", "public_key_raw_base64",
        "public_key_sha256", "issuer_identity_sha256", "allowed_pass_purpose", "normal_executor_authorized", "raw_values",
    ])
    let issuerRaw = try Data(base64Encoded: string(issuer["public_key_raw_base64"])) ?? { try reject() }()
    let issuerAuthority = try string(issuer["authority_sha"])
    let issuerGeneration = try string(issuer["issuer_generation_id"])
    let issuerIdentity = sha256(Data((issuerAuthority + issuerGeneration).utf8) + issuerRaw)
    guard issuerRaw.count == 32, try integer(issuer["schema_version"]) == 1,
          try string(issuer["purpose"]) == "CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1", try string(issuer["authority_sha"]) == authority,
          isGeneration(issuerGeneration), try string(issuer["public_key_algorithm"]) == "Ed25519",
          try string(issuer["public_key_sha256"]) == sha256(issuerRaw),
          try string(issuer["issuer_identity_sha256"]) == issuerIdentity,
          try string(issuer["allowed_pass_purpose"]) == "CI3_VPS_OPERATION_AUTHORITY_PASS_V1",
          try boolean(issuer["normal_executor_authorized"]) == false, try boolean(issuer["raw_values"]) == false else { try reject() }
    try exactKeys(pass, [
        "schema_version", "purpose", "authority_sha", "authority_parent", "authority_tree", "authority_subject_sha256", "authority_manifest_sha256",
        "operation_authority_sha256", "node_candidate_sha256", "collector_contracts_sha256", "publisher_input_manifest_sha256", "remote_generation_id",
        "controller_generation_id", "transfer_payload_sha256", "issuer_authority_sha256", "issuer_key_sha256", "source_generation_id", "attempt", "retry",
        "raw_values", "signed_payload_sha256", "signature_base64",
    ])
    var signed = pass
    let signatureText = try string(signed.removeValue(forKey: "signature_base64"))
    let signedHash = try string(signed.removeValue(forKey: "signed_payload_sha256"))
    let signedBytes = try canonicalJSON(signed)
    guard let signature = Data(base64Encoded: signatureText), signature.count == 64 else { try reject() }
    guard try integer(pass["schema_version"]) == 1, try string(pass["purpose"]) == "CI3_VPS_OPERATION_AUTHORITY_PASS_V1",
          try string(pass["authority_sha"]) == authority, try string(pass["remote_generation_id"]) == remote,
          try string(pass["controller_generation_id"]) == generation, try string(pass["issuer_authority_sha256"]) == sha256(try canonicalJSON(issuer)),
          try string(pass["issuer_key_sha256"]) == sha256(issuerRaw),
          try string(pass["authority_sha"]) == string(projection["authority_sha"]),
          try string(pass["authority_parent"]) == string(projection["authority_parent"]),
          try string(pass["authority_tree"]) == string(projection["authority_tree"]),
          try string(pass["authority_subject_sha256"]) == string(projection["authority_subject_sha256"]),
          try string(pass["authority_manifest_sha256"]) == string(projection["authority_manifest_sha256"]),
          try string(pass["operation_authority_sha256"]) == string(projection["operation_authority_sha256"]),
          try string(pass["node_candidate_sha256"]) == string(projection["node_candidate_sha256"]),
          try string(pass["collector_contracts_sha256"]) == string(projection["collector_contracts_sha256"]),
          try string(pass["remote_generation_id"]) == string(projection["remote_generation_id"]),
          try string(pass["controller_generation_id"]) == string(projection["controller_generation_id"]),
          try string(pass["authority_manifest_sha256"]) == gate0Manifest,
          try string(pass["source_generation_id"]) == "src-\(sha256(try canonicalJSON(issuer)))", try integer(pass["attempt"]) == 1,
          try boolean(pass["retry"]) == false, try boolean(pass["raw_values"]) == false else { try reject() }
    guard signedHash == sha256(signedBytes) else { try reject() }
    guard try Curve25519.Signing.PublicKey(rawRepresentation: issuerRaw).isValidSignature(signature, for: signedBytes) else { try reject() }
    try exactKeys(manifest, ["schema_version", "purpose", "authority_sha", "remote_generation_id", "controller_generation_id", "collector_contracts_sha256", "entries", "transfer_payload_sha256", "raw_values"])
    let transportEntries = try array(manifest["entries"])
    guard try integer(manifest["schema_version"]) == 1, try string(manifest["purpose"]) == "CI3_VPS_PUBLISHER_INPUT_MANIFEST_V2",
          try string(manifest["authority_sha"]) == authority, try string(manifest["remote_generation_id"]) == remote,
          try string(manifest["controller_generation_id"]) == generation, transportEntries.count == transportRoles.count,
          try boolean(manifest["raw_values"]) == false, try string(manifest["transfer_payload_sha256"]) == sha256(try canonicalJSON(transportEntries)),
          try string(pass["publisher_input_manifest_sha256"]) == sha256(try canonicalJSON(manifest)),
          try string(pass["transfer_payload_sha256"]) == string(manifest["transfer_payload_sha256"]) else { try reject() }
    for (index, entry) in transportEntries.enumerated() {
        try exactKeys(entry, ["role", "path_sha256", "sha256"])
        guard try string(entry["role"]) == transportRoles[index], isHex(try string(entry["path_sha256"])), isHex(try string(entry["sha256"])) else { try reject() }
    }
    try exactKeys(installerProvenance, [
        "git_path", "git_blob_oid", "source_sha256", "authority_manifest_sha256",
        "compile_authority_sha256", "expected_binary_sha256",
    ])
    guard try string(installerProvenance["git_path"]) == "scripts/ci3/ci3-publisher1-bootstrap-installer.swift",
          isHex(try string(installerProvenance["git_blob_oid"]), 40),
          isHex(try string(installerProvenance["source_sha256"])),
          try string(installerProvenance["authority_manifest_sha256"]) == gate0Manifest,
          isHex(try string(installerProvenance["compile_authority_sha256"])),
          isHex(try string(installerProvenance["expected_binary_sha256"])) else { try reject() }
    try exactKeys(humanRequest, [
        "schema_version", "purpose", "authority_sha", "authority_manifest_sha256", "operation_authority_sha256", "authority_projection_sha256",
        "publisher_input_manifest_sha256", "vps_operation_authority_pass_sha256", "issuer_authority_sha256",
        "receiver_root_path_sha256", "receiver_root_identity_sha256", "receiver_leaves_sha256",
        "installer_provenance", "prompt_sha256", "prompt_budget", "attempt", "retry", "raw_values",
    ])
    guard try integer(humanRequest["schema_version"]) == 2,
          try string(humanRequest["purpose"]) == "CI3_HUMAN_AUTHORIZATION_REQUEST_V2",
          try string(humanRequest["authority_sha"]) == authority,
          try string(humanRequest["authority_manifest_sha256"]) == gate0Manifest,
          try string(humanRequest["operation_authority_sha256"]) == string(pass["operation_authority_sha256"]),
          try string(humanRequest["authority_projection_sha256"]) == projectionHash,
          try string(humanRequest["publisher_input_manifest_sha256"]) == sha256(try canonicalJSON(manifest)),
          try string(humanRequest["vps_operation_authority_pass_sha256"]) == sha256(try canonicalJSON(pass)),
          try string(humanRequest["issuer_authority_sha256"]) == sha256(try canonicalJSON(issuer)),
          try canonicalJSON(object(humanRequest["installer_provenance"])) == canonicalJSON(installerProvenance),
          try string(humanRequest["prompt_sha256"]) == string(handoff["prompt_sha256"]),
          try integer(humanRequest["prompt_budget"]) == 1,
          try integer(humanRequest["attempt"]) == 1, try boolean(humanRequest["retry"]) == false,
          try boolean(humanRequest["raw_values"]) == false else { try reject() }
    try exactKeys(humanRequestObservation, [
        "role", "path", "path_sha256", "sha256", "uid", "gid", "mode", "nlink", "size",
        "mtime_ns", "dev", "ino", "identity_sha256",
    ])
    let humanRequestPhysical = Physical(
        uid: try integer(humanRequestObservation["uid"]), gid: try integer(humanRequestObservation["gid"]),
        mode: try integer(humanRequestObservation["mode"]), nlink: try integer(humanRequestObservation["nlink"]),
        size: try integer(humanRequestObservation["size"]), mtimeNS: try string(humanRequestObservation["mtime_ns"]),
        dev: try string(humanRequestObservation["dev"]), ino: try string(humanRequestObservation["ino"])
    )
    guard try string(humanRequestObservation["role"]) == "human-authorization-request",
          safeAbsolutePath(try string(humanRequestObservation["path"])),
          try string(humanRequestObservation["path_sha256"]) == sha256(Data(string(humanRequestObservation["path"]).utf8)),
          try string(humanRequestObservation["sha256"]) == sha256(try canonicalJSON(humanRequest)),
          humanRequestPhysical.uid > 0, humanRequestPhysical.gid > 0,
          humanRequestPhysical.mode == 0o600, humanRequestPhysical.nlink == 1,
          try string(humanRequestObservation["identity_sha256"]) == humanRequestPhysical.identity() else { try reject() }
    try exactKeys(human, [
        "schema_version", "purpose", "authority_sha", "approved_action", "authority_manifest_sha256",
        "operation_authority_sha256", "authority_projection_sha256", "publisher_input_manifest_sha256", "vps_operation_authority_pass_sha256",
        "issuer_authority_sha256", "node_binary_sha256", "authorization_request_path_sha256",
        "authorization_request_sha256", "authorization_request_identity_sha256", "authorization_request_uid",
        "authorization_request_gid", "authorization_request_mode", "authorization_request_nlink",
        "receiver_root_path_sha256", "receiver_root_identity_sha256", "receiver_leaves_sha256",
        "publisher_installer_git_path", "publisher_installer_git_blob_oid", "publisher_installer_source_sha256",
        "publisher_installer_provenance_sha256", "publisher_installer_compile_authority_sha256",
        "publisher_installer_expected_binary_sha256", "prompt_sha256", "prompt_budget", "authorized_uid",
        "authorized_gid", "confirmation_sha256", "attempt", "retry", "raw_values",
    ])
    guard try integer(human["schema_version"]) == 2, try string(human["purpose"]) == "CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V2",
          try string(human["authority_sha"]) == authority, try string(human["approved_action"]) == "PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY",
          try string(human["authority_manifest_sha256"]) == gate0Manifest,
          try string(human["operation_authority_sha256"]) == string(pass["operation_authority_sha256"]),
          try string(human["authority_projection_sha256"]) == projectionHash,
          try string(human["authority_projection_sha256"]) == string(humanRequest["authority_projection_sha256"]),
          try string(human["publisher_input_manifest_sha256"]) == sha256(try canonicalJSON(manifest)),
          try string(human["vps_operation_authority_pass_sha256"]) == sha256(try canonicalJSON(pass)),
          try string(human["issuer_authority_sha256"]) == sha256(try canonicalJSON(issuer)),
          try string(human["node_binary_sha256"]) == string(pass["node_candidate_sha256"]),
          try string(human["authorization_request_path_sha256"]) == string(humanRequestObservation["path_sha256"]),
          try string(human["authorization_request_sha256"]) == string(humanRequestObservation["sha256"]),
          try string(human["authorization_request_identity_sha256"]) == string(humanRequestObservation["identity_sha256"]),
          try integer(human["authorization_request_uid"]) == humanRequestPhysical.uid,
          try integer(human["authorization_request_gid"]) == humanRequestPhysical.gid,
          try integer(human["authorization_request_mode"]) == 0o600,
          try integer(human["authorization_request_nlink"]) == 1,
          try string(human["receiver_root_path_sha256"]) == string(humanRequest["receiver_root_path_sha256"]),
          try string(human["receiver_root_identity_sha256"]) == string(humanRequest["receiver_root_identity_sha256"]),
          try string(human["receiver_leaves_sha256"]) == string(humanRequest["receiver_leaves_sha256"]),
          try string(human["publisher_installer_git_path"]) == string(installerProvenance["git_path"]),
          try string(human["publisher_installer_git_blob_oid"]) == string(installerProvenance["git_blob_oid"]),
          try string(human["publisher_installer_source_sha256"]) == string(installerProvenance["source_sha256"]),
          try string(human["publisher_installer_provenance_sha256"]) == sha256(try canonicalJSON(installerProvenance)),
          try string(human["publisher_installer_compile_authority_sha256"]) == string(installerProvenance["compile_authority_sha256"]),
          try string(human["publisher_installer_expected_binary_sha256"]) == string(installerProvenance["expected_binary_sha256"]),
          try string(human["prompt_sha256"]) == string(handoff["prompt_sha256"]),
          try integer(human["prompt_budget"]) == 1,
          try integer(human["authorized_uid"]) > 0, try integer(human["authorized_gid"]) > 0,
          isHex(try string(human["confirmation_sha256"])),
          try integer(human["attempt"]) == 1, try boolean(human["retry"]) == false, try boolean(human["raw_values"]) == false else { try reject() }
    try exactKeys(materializer, [
        "schema_version", "purpose", "authority_sha", "controller_generation_id", "issuer_authority_sha256", "materializer_path", "materializer_path_sha256",
        "materializer_sha256", "writer_source_sha256", "request_path_sha256", "request_sha256", "request_identity_sha256", "request_uid", "request_gid",
        "request_mode", "request_nlink", "receiver_root_path_sha256", "receiver_root_identity_sha256", "receiver_leaves", "allowed_environment", "normal_executor_authorized", "raw_values",
    ])
    let materializerLeaves = try array(materializer["receiver_leaves"])
    let allowedEnvironment = try object(materializer["allowed_environment"])
    let expectedMaterializerPath = "/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/\(authority)/bootstrap-\(try string(projection["authority_manifest_sha256"]))/runtime/ci3-terminal-anchor-writer"
    guard try integer(materializer["schema_version"]) == 2, try string(materializer["purpose"]) == "CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2",
          try string(materializer["authority_sha"]) == authority, try string(materializer["controller_generation_id"]) == generation,
          try string(materializer["issuer_authority_sha256"]) == sha256(try canonicalJSON(issuer)),
          try string(materializer["materializer_path"]) == expectedMaterializerPath,
          try string(materializer["materializer_path_sha256"]) == sha256(Data((try string(materializer["materializer_path"])).utf8)),
          isHex(try string(materializer["materializer_sha256"])),
          isHex(try string(materializer["writer_source_sha256"])),
          try integer(materializer["request_mode"]) == 0o600, try integer(materializer["request_nlink"]) == 1,
          try integer(materializer["request_uid"]) > 0, try integer(materializer["request_gid"]) > 0,
          try string(materializer["receiver_root_path_sha256"]) == string(handoff["receiver_root_path_sha256"]),
          try string(materializer["receiver_root_identity_sha256"]) == string(handoff["receiver_root_identity_sha256"]),
          materializerLeaves.count == receiverRoles.count, try canonicalJSON(materializerLeaves) == canonicalJSON(leaves),
          try boolean(materializer["normal_executor_authorized"]) == false, try boolean(materializer["raw_values"]) == false else { try reject() }
    try exactKeys(allowedEnvironment, ["HOME", "LANG", "LC_ALL", "PATH"])
    guard try string(allowedEnvironment["HOME"]) == "/var/empty", try string(allowedEnvironment["LANG"]) == "C",
          try string(allowedEnvironment["LC_ALL"]) == "C", try string(allowedEnvironment["PATH"]) == "/usr/bin:/bin" else { try reject() }
    for (index, leaf) in leaves.enumerated() {
        let uid = try integer(leaf["uid"])
        let gid = try integer(leaf["gid"])
        let mode = try integer(leaf["mode"])
        let nlink = try integer(leaf["nlink"])
        let size = try integer(leaf["size"])
        let mtime = try string(leaf["mtime_ns"])
        let dev = try string(leaf["dev"])
        let ino = try string(leaf["ino"])
        let identity = try string(leaf["identity_sha256"])
        try exactKeys(leaf, ["role", "path_sha256", "sha256", "uid", "gid", "mode", "nlink", "size", "mtime_ns", "dev", "ino", "identity_sha256"])
        guard try string(leaf["role"]) == receiverRoles[index], mode == 0o600, nlink == 1,
              uid > 0, gid > 0, size >= 0, uid <= nodeSafeMaximum, gid <= nodeSafeMaximum,
              nlink <= nodeSafeMaximum, size <= nodeSafeMaximum,
              isHex(try string(leaf["path_sha256"])), isHex(try string(leaf["sha256"])), isHex(try string(leaf["identity_sha256"])),
              try canonicalDecimal(mtime, maximum: UInt64(Int64.max)) <= UInt64(Int64.max),
              try canonicalDecimal(dev, maximum: UInt64.max) <= UInt64.max,
              try canonicalDecimal(ino, maximum: UInt64.max) <= UInt64.max,
              Physical(uid: uid, gid: gid, mode: mode, nlink: nlink, size: size, mtimeNS: mtime, dev: dev, ino: ino).identity() == identity else { try reject() }
    }
    for (offset, entry) in entries.dropFirst(3).enumerated() {
        let leaf = leaves[offset]
        let leafRole = try string(leaf["role"])
        let leafSHA = try string(leaf["sha256"])
        let leafPathSHA = try string(leaf["path_sha256"])
        let leafUID = try integer(leaf["uid"])
        let leafGID = try integer(leaf["gid"])
        let leafMode = try integer(leaf["mode"])
        let leafNlink = try integer(leaf["nlink"])
        let leafSize = try integer(leaf["size"])
        let leafMtime = try string(leaf["mtime_ns"])
        let leafDev = try string(leaf["dev"])
        let leafIno = try string(leaf["ino"])
        let leafIdentity = try string(leaf["identity_sha256"])
        guard entry.role == leafRole, entry.sourceSHA == leafSHA,
              sha256(Data(entry.sourcePath.utf8)) == leafPathSHA,
              entry.physical.uid == leafUID, entry.physical.gid == leafGID,
              entry.physical.mode == leafMode, entry.physical.nlink == leafNlink,
              entry.physical.size == leafSize, entry.physical.mtimeNS == leafMtime,
              entry.physical.dev == leafDev, entry.physical.ino == leafIno,
              entry.physical.identity() == leafIdentity else { try reject() }
    }
    let materializerBytes = try canonicalJSON(materializer)
    let issuerBytes = try canonicalJSON(issuer)
    let materializerHash = try string(materializer["materializer_sha256"])
    let writerHash = try string(materializer["writer_source_sha256"])
    guard entries.count == expectedRoles.count, entries[0].bytes == materializerBytes, entries[1].bytes == issuerBytes,
          entries[2].sourceSHA == materializerHash, isHex(writerHash) else { try reject() }
}

private struct Request {
    let authority: String
    let generation: String
    let destination: String
    let state: String
    let handoff: [String: Any]
    let entries: [Entry]
    let hash: String
}

private let transportRoles = [
    "node-runtime", "controller", "launcher-runtime", "launch-attestation", "authority-manifest",
    "operation-authority", "ssh-config", "ssh-known-hosts", "ssh-private-key", "ssh-public-key", "ssh-trust-descriptor",
]

private let receiverRoles = [
    "node-runtime", "controller", "launcher-runtime", "launcher-bootstrap-authority", "launch-attestation", "authority-manifest",
    "operation-authority", "human-authorization", "vps-pass", "vps-issuer-authority", "publisher-input-manifest", "ssh-config",
    "ssh-known-hosts", "ssh-private-key", "ssh-public-key", "ssh-trust-descriptor",
]

// The local preparation phase is causally prior to Publisher0. Only the SSH
// bootstrap config exists here; every receiver/request/human/installer object
// is a later output and must not be accepted as a prepared candidate.
private let localPrepareRoles = ["ssh-config"]

private func canonicalJSON(_ value: Any) throws -> Data {
    guard JSONSerialization.isValidJSONObject(value) else { try reject() }
    var bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    bytes.append(0x0a)
    return bytes
}

private func parseRequest(_ arguments: [String]) throws -> Request {
    guard arguments.count == 3 else { try reject() }
    guard arguments[0] == "--install" else { try reject() }
    guard safeAbsolutePath(arguments[1]) else { try reject() }
    guard isHex(arguments[2]) else { try reject() }
    let pinned = try openPinnedFile(arguments[1])
    defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
    guard pinned.before.mode == 0o600 else { try reject() }
    let bytes = try readDescriptor(pinned.descriptor)
    let after = try physical(try fstatValue(pinned.descriptor))
    var relative = stat()
    guard after.identity() == pinned.before.identity(),
          pinned.leaf.withCString({ Darwin.fstatat(pinned.parent, $0, &relative, AT_SYMLINK_NOFOLLOW) }) == 0,
          (try physical(relative)).identity() == pinned.before.identity() else { try reject() }
    guard sha256(bytes) == arguments[2] else { try reject() }
    guard let raw = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { try reject() }
    try exactKeys(raw, [
        "schema_version", "purpose", "authority_sha", "controller_generation_id", "destination_root", "state_root",
        "handoff", "entries", "attempt", "retry", "raw_values",
    ])
    let authority = try string(raw["authority_sha"])
    let generation = try string(raw["controller_generation_id"])
    let requestedDestination = try string(raw["destination_root"])
    let requestedState = try string(raw["state_root"])
    let handoff = try object(raw["handoff"])
    let projection = try object(handoff["authority_projection"])
    let bootstrapDigest = try string(projection["authority_manifest_sha256"])
    guard try integer(raw["schema_version"]) == 2,
          try string(raw["purpose"]) == "CI3_PUBLISHER1_BOOTSTRAP_INSTALL_REQUEST_V2",
          isHex(authority, 40), isGeneration(generation), isHex(bootstrapDigest), safeAbsolutePath(requestedDestination), safeAbsolutePath(requestedState),
          try integer(raw["attempt"]) == 1, try boolean(raw["retry"]) == false, try boolean(raw["raw_values"]) == false else { try reject() }
#if CI3_SYNTHETIC_TEST
    let environment = ProcessInfo.processInfo.environment
    let destination: String
    let state: String
    if let mainRoot = environment["CI3_SYNTHETIC_MAIN_ROOT"] {
        guard safeAbsolutePath(mainRoot),
              requestedDestination == "/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/\(authority)/bootstrap-\(bootstrapDigest)",
              requestedState == "/Library/Application Support/Agentempp/ci3-publisher1-state/\(authority)/\(generation)" else { try reject() }
        destination = (mainRoot as NSString).appendingPathComponent("publisher1-install-base/\(authority)/bootstrap-\(bootstrapDigest)")
        state = (mainRoot as NSString).appendingPathComponent("publisher1-state-base/\(authority)/\(generation)")
    } else {
        guard let installBase = environment["CI3_SYNTHETIC_INSTALL_BASE"],
              let stateBase = environment["CI3_SYNTHETIC_STATE_BASE"],
              safeAbsolutePath(installBase), safeAbsolutePath(stateBase),
              requestedDestination == (installBase as NSString).appendingPathComponent("\(authority)/bootstrap-\(bootstrapDigest)"),
              requestedState == (stateBase as NSString).appendingPathComponent("\(authority)/\(generation)") else { try reject() }
        destination = (installBase as NSString).appendingPathComponent("\(authority)/bootstrap-\(bootstrapDigest)")
        state = (stateBase as NSString).appendingPathComponent("\(authority)/\(generation)")
    }
#else
    let installBase = "/Library/Application Support/Agentempp/ci3-publisher1-bootstrap"
    let stateBase = "/Library/Application Support/Agentempp/ci3-publisher1-state"
    guard getuid() == 0,
          requestedDestination == (installBase as NSString).appendingPathComponent("\(authority)/bootstrap-\(bootstrapDigest)"),
          requestedState == (stateBase as NSString).appendingPathComponent("\(authority)/\(generation)") else { try reject() }
    let destination = requestedDestination
    let state = requestedState
#endif
    let records = try array(raw["entries"])
    guard records.count == expectedRoles.count else { try reject() }
    let entries = try records.enumerated().map { try validateEntry($0.element, index: $0.offset) }
    try validateHandoff(handoff, authority: authority, generation: generation, entries: entries)
    return Request(authority: authority, generation: generation, destination: destination, state: state,
                   handoff: handoff, entries: entries, hash: sha256(bytes))
}

private struct ImmutableBootstrapEnvelope {
    let authority: String
    let generation: String
    let envelopePath: String
    let envelopeHash: String
    let envelopePhysical: Physical
    let requestPath: String
    let requestHash: String
    let preflightPath: String
    let preflightHash: String
    let compileAuthorityHash: String
    let expectedInstallerHash: String
    let installerHash: String
    let installerRoot: String
    let request: Request
}

private func boundOwnerFile(
    _ path: String, expectedHash: String, expectedIdentity: String,
    expectedUID: Int, expectedGID: Int
) throws -> (Data, Physical) {
    let pinned = try openPinnedFile(path)
    defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
    guard pinned.before.uid == expectedUID, pinned.before.gid == expectedGID,
          pinned.before.mode == 0o600, pinned.before.nlink == 1,
          pinned.before.identity() == expectedIdentity else { try reject() }
    let bytes = try readDescriptor(pinned.descriptor)
    let after = try physical(try fstatValue(pinned.descriptor))
    var named = stat()
    guard sha256(bytes) == expectedHash, after.identity() == pinned.before.identity(),
          pinned.leaf.withCString({ Darwin.fstatat(pinned.parent, $0, &named, AT_SYMLINK_NOFOLLOW) }) == 0,
          (try physical(named)).identity() == pinned.before.identity() else { try reject() }
    return (bytes, pinned.before)
}

private func immutableInstallerRoot(_ authority: String, _ generation: String, requested: String) throws -> String {
#if CI3_SYNTHETIC_TEST
    guard let base = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_INSTALLER_BASE"],
          safeAbsolutePath(base) else { try reject() }
#else
    let base = "/Library/Application Support/Agentempp/ci3-publisher1-installer"
#endif
    let exact = (base as NSString).appendingPathComponent("\(authority)/\(generation)")
    guard requested == exact else { try reject() }
    return exact
}

private func validateSemanticPreflightReceipt(
    _ bytes: Data, authority: String, generation: String, requestHash: String,
    compileAuthorityHash: String, expectedInstallerHash: String
) throws {
    guard let receipt = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          try canonicalJSON(receipt) == bytes else { try reject() }
    try exactKeys(receipt, [
        "schema_version", "purpose", "authority_sha", "remote_generation_id", "controller_generation_id",
        "bootstrap_request_sha256", "descriptor_request_sha256", "descriptor_request_identity_sha256",
        "receiver_root_path_sha256", "receiver_root_identity_sha256", "validation_binary_sha256",
        "semantic_sources_sha256", "publisher_installer_compile_authority_sha256",
        "publisher_installer_expected_binary_sha256", "status", "writes_performed", "effect_executions", "network_calls",
        "privilege_prompts", "attempt", "retry", "raw_values",
    ])
    guard try integer(receipt["schema_version"]) == 1,
          try string(receipt["purpose"]) == "CI3_PUBLISHER1_SEMANTIC_PREFLIGHT_RECEIPT_V1",
          try string(receipt["authority_sha"]) == authority,
          isGeneration(try string(receipt["remote_generation_id"])),
          try string(receipt["controller_generation_id"]) == generation,
          try string(receipt["bootstrap_request_sha256"]) == requestHash,
          isHex(try string(receipt["descriptor_request_sha256"])),
          isHex(try string(receipt["descriptor_request_identity_sha256"])),
          isHex(try string(receipt["receiver_root_path_sha256"])),
          isHex(try string(receipt["receiver_root_identity_sha256"])),
          isHex(try string(receipt["validation_binary_sha256"])),
          isHex(try string(receipt["semantic_sources_sha256"])),
          try string(receipt["publisher_installer_compile_authority_sha256"]) == compileAuthorityHash,
          try string(receipt["publisher_installer_expected_binary_sha256"]) == expectedInstallerHash,
          try string(receipt["status"]) == "PASS",
          try integer(receipt["writes_performed"]) == 0,
          try integer(receipt["effect_executions"]) == 0,
          try integer(receipt["network_calls"]) == 0,
          try integer(receipt["privilege_prompts"]) == 0,
          try integer(receipt["attempt"]) == 1,
          try boolean(receipt["retry"]) == false,
          try boolean(receipt["raw_values"]) == false else { try reject() }
}

private func parseImmutableBootstrapEnvelope(_ arguments: [String], phase: String) throws -> ImmutableBootstrapEnvelope {
    guard arguments.count == 3, arguments[0] == phase,
          safeAbsolutePath(arguments[1]), isHex(arguments[2]) else { try reject() }
    let pinned = try openPinnedFile(arguments[1])
    defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
    guard pinned.before.mode == 0o600, pinned.before.nlink == 1 else { try reject() }
    let bytes = try readDescriptor(pinned.descriptor)
    let after = try physical(try fstatValue(pinned.descriptor))
    var named = stat()
    guard sha256(bytes) == arguments[2], after.identity() == pinned.before.identity(),
          pinned.leaf.withCString({ Darwin.fstatat(pinned.parent, $0, &named, AT_SYMLINK_NOFOLLOW) }) == 0,
          (try physical(named)).identity() == pinned.before.identity(),
          let raw = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          try canonicalJSON(raw) == bytes else { try reject() }
    try exactKeys(raw, [
        "schema_version", "purpose", "authority_sha", "controller_generation_id",
        "bootstrap_request_path", "bootstrap_request_path_sha256", "bootstrap_request_sha256",
        "bootstrap_request_identity_sha256", "bootstrap_request_uid", "bootstrap_request_gid",
        "semantic_preflight_receipt_path", "semantic_preflight_receipt_path_sha256",
        "semantic_preflight_receipt_sha256", "semantic_preflight_receipt_identity_sha256",
        "semantic_preflight_receipt_uid", "semantic_preflight_receipt_gid",
        "installer_compile_authority_sha256", "installer_expected_binary_sha256", "installer_sha256",
        "installer_root", "attempt", "retry", "raw_values",
    ])
    let authority = try string(raw["authority_sha"])
    let generation = try string(raw["controller_generation_id"])
    let requestPath = try string(raw["bootstrap_request_path"])
    let requestHash = try string(raw["bootstrap_request_sha256"])
    let preflightPath = try string(raw["semantic_preflight_receipt_path"])
    let preflightHash = try string(raw["semantic_preflight_receipt_sha256"])
    let compileAuthorityHash = try string(raw["installer_compile_authority_sha256"])
    let expectedInstallerHash = try string(raw["installer_expected_binary_sha256"])
    let installerHash = try string(raw["installer_sha256"])
    let installerRoot = try immutableInstallerRoot(authority, generation, requested: string(raw["installer_root"]))
    guard try integer(raw["schema_version"]) == 1,
          try string(raw["purpose"]) == "PUBLISHER1_IMMUTABLE_INSTALLER_BOOTSTRAP_V1",
          isHex(authority, 40), isGeneration(generation),
          safeAbsolutePath(requestPath), safeAbsolutePath(preflightPath),
          try string(raw["bootstrap_request_path_sha256"]) == sha256(Data(requestPath.utf8)),
          try string(raw["semantic_preflight_receipt_path_sha256"]) == sha256(Data(preflightPath.utf8)),
          isHex(requestHash), isHex(preflightHash), isHex(compileAuthorityHash),
          isHex(expectedInstallerHash), isHex(installerHash), installerHash == expectedInstallerHash,
          try integer(raw["attempt"]) == 1, try boolean(raw["retry"]) == false,
          try boolean(raw["raw_values"]) == false else { try reject() }
    let (requestBytes, _) = try boundOwnerFile(
        requestPath, expectedHash: requestHash,
        expectedIdentity: string(raw["bootstrap_request_identity_sha256"]),
        expectedUID: integer(raw["bootstrap_request_uid"]), expectedGID: integer(raw["bootstrap_request_gid"])
    )
    let (preflightBytes, _) = try boundOwnerFile(
        preflightPath, expectedHash: preflightHash,
        expectedIdentity: string(raw["semantic_preflight_receipt_identity_sha256"]),
        expectedUID: integer(raw["semantic_preflight_receipt_uid"]), expectedGID: integer(raw["semantic_preflight_receipt_gid"])
    )
    let request = try parseRequest(["--install", requestPath, requestHash])
    guard sha256(requestBytes) == request.hash, request.authority == authority,
          request.generation == generation else { try reject() }
    let gate0 = try object(request.handoff["gate0_receipt"])
    if try string(gate0["purpose"]) == "CI3_SEMANTIC_SAFE_MAC_GATE0_V2" {
        let human = try object(request.handoff["human_authorization"])
        guard try string(human["publisher_installer_compile_authority_sha256"]) == compileAuthorityHash,
              try string(human["publisher_installer_expected_binary_sha256"]) == expectedInstallerHash else { try reject() }
    }
    try validateSemanticPreflightReceipt(
        preflightBytes, authority: authority, generation: generation, requestHash: requestHash,
        compileAuthorityHash: compileAuthorityHash, expectedInstallerHash: expectedInstallerHash
    )
    return ImmutableBootstrapEnvelope(
        authority: authority, generation: generation, envelopePath: arguments[1], envelopeHash: arguments[2],
        envelopePhysical: pinned.before, requestPath: requestPath, requestHash: requestHash,
        preflightPath: preflightPath, preflightHash: preflightHash,
        compileAuthorityHash: compileAuthorityHash, expectedInstallerHash: expectedInstallerHash,
        installerHash: installerHash,
        installerRoot: installerRoot, request: request
    )
}

private func immutableBootstrapReceipt(_ envelope: ImmutableBootstrapEnvelope, installedPath: String) throws -> Data {
    try canonicalJSON([
        "schema_version": 1, "purpose": "PUBLISHER1_IMMUTABLE_INSTALLER_BOOTSTRAP_RECEIPT_V1",
        "authority_sha": envelope.authority, "controller_generation_id": envelope.generation,
        "envelope_sha256": envelope.envelopeHash, "envelope_identity_sha256": envelope.envelopePhysical.identity(),
        "bootstrap_request_sha256": envelope.requestHash,
        "semantic_preflight_receipt_sha256": envelope.preflightHash,
        "installer_compile_authority_sha256": envelope.compileAuthorityHash,
        "installer_expected_binary_sha256": envelope.expectedInstallerHash,
        "installer_sha256": envelope.installerHash,
        "installed_path_sha256": sha256(Data(installedPath.utf8)),
        "status": "PASS", "phase_a_target_writes": 0,
        "attempt": 1, "retry": false, "raw_values": false,
    ])
}

private func immutableMetadata(_ descriptor: Int32, mode: Int) throws {
    let observed = try fstatValue(descriptor)
    let value = try physical(observed)
    guard value.mode == mode, value.nlink == 1 else { try reject() }
    if productionMetadataRequired() {
        guard value.uid == Int(expectedPublishedUID()), value.gid == Int(expectedPublishedGID()),
              (observed.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try reject() }
    }
}

private func verifyImmutableInstallerTree(_ envelope: ImmutableBootstrapEnvelope) throws -> String {
    let chain = try openDirectoryChain(envelope.installerRoot, create: false)
    defer { for descriptor in chain.reversed() { Darwin.close(descriptor) } }
    let root = chain.last!
    try requireExactDirectoryChildren(root, ["runtime", "immutable-installer-bootstrap.receipt.json"])
    let runtime = try openDirectoryAt(root, "runtime", create: false)
    defer { Darwin.close(runtime) }
    try requireExactDirectoryChildren(runtime, ["ci3-publisher1-bootstrap-installer"])
    let installedPath = (envelope.installerRoot as NSString).appendingPathComponent("runtime/ci3-publisher1-bootstrap-installer")
    let selfDescriptor = Darwin.open(installedPath, O_RDONLY | O_NOFOLLOW)
    guard selfDescriptor >= 0 else { try reject() }
    defer { Darwin.close(selfDescriptor) }
    let selfBytes = try readDescriptor(selfDescriptor)
    try immutableMetadata(selfDescriptor, mode: 0o555)
    guard sha256(selfBytes) == envelope.installerHash else { try reject() }
    let receiptDescriptor = "immutable-installer-bootstrap.receipt.json".withCString {
        Darwin.openat(root, $0, O_RDONLY | O_NOFOLLOW)
    }
    guard receiptDescriptor >= 0 else { try reject() }
    defer { Darwin.close(receiptDescriptor) }
    try immutableMetadata(receiptDescriptor, mode: 0o444)
    guard try readDescriptor(receiptDescriptor) == immutableBootstrapReceipt(envelope, installedPath: installedPath) else { try reject() }
    if productionMetadataRequired() {
        for descriptor in [runtime, root] {
            let observed = try fstatValue(descriptor)
            let value = try physical(observed)
            guard value.uid == Int(expectedPublishedUID()), value.gid == Int(expectedPublishedGID()),
                  value.mode == 0o555, (observed.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try reject() }
        }
    }
    return installedPath
}

private func finishExactPromotedInstallerDirectoryFreeze(_ envelope: ImmutableBootstrapEnvelope) throws -> String {
    let chain = try openDirectoryChain(envelope.installerRoot, create: false)
    defer { for descriptor in chain.reversed() { Darwin.close(descriptor) } }
    let root = chain.last!
    try requireExactDirectoryChildren(root, ["runtime", "immutable-installer-bootstrap.receipt.json"])
    let runtime = try openDirectoryAt(root, "runtime", create: false)
    defer { Darwin.close(runtime) }
    try requireExactDirectoryChildren(runtime, ["ci3-publisher1-bootstrap-installer"])
    let installedPath = (envelope.installerRoot as NSString).appendingPathComponent("runtime/ci3-publisher1-bootstrap-installer")
    let selfDescriptor = Darwin.open(installedPath, O_RDONLY | O_NOFOLLOW)
    guard selfDescriptor >= 0 else { try reject() }
    defer { Darwin.close(selfDescriptor) }
    try immutableMetadata(selfDescriptor, mode: 0o555)
    guard sha256(try readDescriptor(selfDescriptor)) == envelope.installerHash else { try reject() }
    let receiptDescriptor = "immutable-installer-bootstrap.receipt.json".withCString {
        Darwin.openat(root, $0, O_RDONLY | O_NOFOLLOW)
    }
    guard receiptDescriptor >= 0 else { try reject() }
    defer { Darwin.close(receiptDescriptor) }
    try immutableMetadata(receiptDescriptor, mode: 0o444)
    guard try readDescriptor(receiptDescriptor) == immutableBootstrapReceipt(envelope, installedPath: installedPath) else { try reject() }
    for descriptor in [runtime, root] {
        let observed = try fstatValue(descriptor)
        let value = try physical(observed)
        guard [0o700, 0o555].contains(value.mode), (value.mode & 0o022) == 0 else { try reject() }
        if productionMetadataRequired() {
            guard value.uid == Int(expectedPublishedUID()), value.gid == Int(expectedPublishedGID()) else { try reject() }
        }
    }
    try freezeOwnedDescriptor(runtime, 0o555)
    try freezeOwnedDescriptor(root, 0o555)
    return try verifyImmutableInstallerTree(envelope)
}

private func syntheticPhaseBContinuationRoot(_ envelope: ImmutableBootstrapEnvelope) throws -> String? {
#if CI3_SYNTHETIC_TEST
    guard ProcessInfo.processInfo.environment["CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A"] == "1" else { return nil }
    guard let syntheticRoot = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_MAIN_ROOT"],
          let projectionPath = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_FROZEN_PROJECTION_PATH"],
          safeAbsolutePath(syntheticRoot), safeAbsolutePath(projectionPath) else { try reject() }
    let frozenRoot = (projectionPath as NSString).deletingLastPathComponent
    let artifactRoot = (envelope.envelopePath as NSString).deletingLastPathComponent
    guard projectionPath == (frozenRoot as NSString).appendingPathComponent("frozen-authority-projection.json"),
          frozenRoot.hasPrefix(syntheticRoot + "/"),
          artifactRoot == (frozenRoot as NSString).appendingPathComponent("publisher1-produced"),
          envelope.envelopePath == (artifactRoot as NSString).appendingPathComponent("publisher1-immutable-installer.request.json") else {
        try reject()
    }
    return artifactRoot
#else
    return nil
#endif
}

private func writeSyntheticContinuationMarker(_ artifactRoot: String, _ leaf: String, _ bytes: Data) throws {
    let chain = try openDirectoryChain(artifactRoot, create: false)
    defer { for descriptor in chain.reversed() { Darwin.close(descriptor) } }
    let parent = chain.last!
    if let existing = try readExistingAt(parent, leaf) {
        guard existing == bytes, let metadata = try statAt(parent, leaf),
              (metadata.st_mode & S_IFMT) == S_IFREG,
              (metadata.st_mode & 0o777) == 0o600, metadata.st_nlink == 1,
              metadata.st_uid == getuid(), metadata.st_gid == getgid()
        else { try reject() }
    } else {
        try writeExclusiveAt(parent, leaf, bytes, 0o600, rootOwned: false)
    }
}

private func awaitSyntheticPhaseBContinuation(_ artifactRoot: String?, envelope: ImmutableBootstrapEnvelope) throws {
    guard let artifactRoot else { return }
    try writeSyntheticContinuationMarker(
        artifactRoot, "publisher1-phase-a.settled", Data("PHASE_A_SETTLED_CONTINUING\n".utf8)
    )
    let prepared: [String: Any] = [
        "schema_version": 1,
        "purpose": "CI3_SYNTHETIC_PUBLISHER1_PHASE_B_BARRIER_V1",
        "authority_sha": envelope.authority,
        "controller_generation_id": envelope.generation,
        "immutable_request_sha256": envelope.envelopeHash,
        "installed_self_sha256": envelope.installerHash,
        "stage": "IMMEDIATELY_BEFORE_PHASE_B_OBSERVE_WRITE",
        "decision": "PREPARED",
        "raw_values": false,
    ]
    let preparedBytes = try canonicalJSON(prepared)
    try writeSyntheticContinuationMarker(
        artifactRoot, "publisher1-phase-b.prepared.json", preparedBytes
    )
    let chain = try openDirectoryChain(artifactRoot, create: false)
    defer { for descriptor in chain.reversed() { Darwin.close(descriptor) } }
    let parent = chain.last!
    for _ in 0..<1200 {
        if let gate = try readExistingAt(parent, "publisher1-phase-b.continue.json") {
            let metadata = try statAt(parent, "publisher1-phase-b.continue.json")
            guard let release = try JSONSerialization.jsonObject(with: gate) as? [String: Any],
                  try canonicalJSON(release) == gate else { try reject() }
            try exactKeys(release, [
                "schema_version", "purpose", "authority_sha", "controller_generation_id",
                "immutable_request_sha256", "installed_self_sha256", "prepared_sha256",
                "stage", "decision", "raw_values",
            ])
            guard
                  try integer(release["schema_version"]) == 1,
                  try string(release["purpose"]) == "CI3_SYNTHETIC_PUBLISHER1_PHASE_B_BARRIER_RELEASE_V1",
                  try string(release["authority_sha"]) == envelope.authority,
                  try string(release["controller_generation_id"]) == envelope.generation,
                  try string(release["immutable_request_sha256"]) == envelope.envelopeHash,
                  try string(release["installed_self_sha256"]) == envelope.installerHash,
                  try string(release["prepared_sha256"]) == sha256(preparedBytes),
                  try string(release["stage"]) == "IMMEDIATELY_BEFORE_PHASE_B_OBSERVE_WRITE",
                  try string(release["decision"]) == "CONTINUE",
                  try boolean(release["raw_values"]) == false,
                  let metadata,
                  (metadata.st_mode & S_IFMT) == S_IFREG, (metadata.st_mode & 0o777) == 0o600,
                  metadata.st_nlink == 1, metadata.st_uid == getuid(), metadata.st_gid == getgid() else { try reject() }
            return
        }
        Darwin.usleep(25_000)
    }
    try reject()
}

private struct DurablePhaseBService {
    let identity: String
    let label: String
    let claimPath: String
    let definitionPath: String
    let activationOwnerDefinitionPath: String
    let invocationPath: String
    let registrationPath: String
    let activationOwnerClaimPath: String
    let activationOwnerLockPath: String
    let activationOwnerReadyPath: String
    let kickstartDecisionPath: String
    let physicalKickstartPath: String
    let workerLockPath: String
    let startedPath: String
    let executingPath: String
    let runClaimPath: String
    let effectEntryPath: String
    let completedPath: String
    let failedPath: String
    let stopPartialPath: String
    let settlementPath: String
    let claimBytes: Data
    let definitionBytes: Data
    let activationOwnerDefinitionBytes: Data
    let invocationBytes: Data
    let registrationBytes: Data
    let mode: mode_t
    let synthetic: Bool
}

private func durablePhaseBIdentity(_ envelope: ImmutableBootstrapEnvelope, installedPath: String) throws -> String {
    sha256(try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_SERVICE_IDENTITY_V1",
        "authority_sha": envelope.authority,
        "controller_generation_id": envelope.generation,
        "immutable_request_sha256": envelope.envelopeHash,
        "installed_self_path_sha256": sha256(Data(installedPath.utf8)),
        "installed_self_sha256": envelope.installerHash,
        "raw_values": false,
    ]))
}

private func durablePhaseBDefinition(
    label: String, installedPath: String, envelope: ImmutableBootstrapEnvelope,
    claimPath: String, claimHash: String
) throws -> Data {
    let escape: (String) -> String = { value in
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    let arguments = [
        installedPath, "--durable-immutable-bootstrap-phase-b",
        envelope.envelopePath, envelope.envelopeHash, claimPath, claimHash,
    ].map { "<string>\(escape($0))</string>" }.joined()
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>Label</key><string>\(escape(label))</string><key>ProcessType</key><string>Background</string><key>ProgramArguments</key><array>\(arguments)</array><key>StandardErrorPath</key><string>/dev/null</string><key>StandardInPath</key><string>/dev/null</string><key>StandardOutPath</key><string>/dev/null</string></dict></plist>
    """
    return Data(xml.utf8)
}

private func durablePhaseBActivationOwnerDefinition(
    label: String, installedPath: String, envelope: ImmutableBootstrapEnvelope,
    claimPath: String, claimHash: String
) -> Data {
    let escape: (String) -> String = { value in
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    let ownerLabel = "\(label).activation-owner"
    let arguments = [
        installedPath, "--durable-immutable-bootstrap-activation-owner",
        envelope.envelopePath, envelope.envelopeHash, claimPath, claimHash,
    ].map { "<string>\(escape($0))</string>" }.joined()
    return Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>Label</key><string>\(escape(ownerLabel))</string><key>ProcessType</key><string>Background</string><key>ProgramArguments</key><array>\(arguments)</array><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict><key>StandardErrorPath</key><string>/dev/null</string><key>StandardInPath</key><string>/dev/null</string><key>StandardOutPath</key><string>/dev/null</string></dict></plist>
    """.utf8)
}

private func durablePhaseBService(
    _ envelope: ImmutableBootstrapEnvelope, installedPath: String, artifactRoot: String?
) throws -> DurablePhaseBService {
    let identity = try durablePhaseBIdentity(envelope, installedPath: installedPath)
    let label = "com.agentempp.ci3.publisher1.\(identity)"
    let synthetic = artifactRoot != nil
    let stateRoot = artifactRoot ?? "/Library/Application Support/Agentempp/ci3-publisher1-continuations/\(identity)"
    let claimPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.service.json")
    let definitionPath = synthetic
        ? (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.launchd.plist")
        : "/Library/LaunchDaemons/\(label).plist"
    let activationOwnerDefinitionPath = synthetic
        ? (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.activation-owner.plist")
        : "/Library/LaunchDaemons/\(label).activation-owner.plist"
    let invocationPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.invocation.json")
    let registrationPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.registration.json")
    let activationOwnerClaimPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.activation-owner.json")
    let activationOwnerLockPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.activation-owner-lock.json")
    let activationOwnerReadyPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.activation-owner-ready.json")
    let kickstartDecisionPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.kickstart-decided.json")
    let physicalKickstartPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.physical-kickstart.json")
    let workerLockPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.worker-lock.json")
    let startedPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.started.json")
    let executingPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.executing.json")
    let runClaimPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.run-claim.json")
    let effectEntryPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.effect-entry.json")
    let completedPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.completed.json")
    let failedPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.failed.json")
    let stopPartialPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.stop-partial.json")
    let settlementPath = (stateRoot as NSString).appendingPathComponent("publisher1-durable-phase-b.service-settled.json")
    let claimBytes = try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_SERVICE_V1",
        "authority_sha": envelope.authority,
        "controller_generation_id": envelope.generation,
        "immutable_request_path_sha256": sha256(Data(envelope.envelopePath.utf8)),
        "immutable_request_sha256": envelope.envelopeHash,
        "installed_self_path_sha256": sha256(Data(installedPath.utf8)),
        "installed_self_sha256": envelope.installerHash,
        "service_identity_sha256": identity,
        "service_kind": "VERSION_ADDRESSED_PERSISTENT_CONTINUATION",
        "admin_prompt_budget": 1,
        "phase_a_attempt": 1,
        "retry": false,
        "raw_values": false,
    ])
    let definitionBytes = try durablePhaseBDefinition(
        label: label, installedPath: installedPath, envelope: envelope,
        claimPath: claimPath, claimHash: sha256(claimBytes)
    )
    let activationOwnerDefinitionBytes = durablePhaseBActivationOwnerDefinition(
        label: label, installedPath: installedPath, envelope: envelope,
        claimPath: claimPath, claimHash: sha256(claimBytes)
    )
    let invocationBytes = try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_WORKER_INVOCATION_V1",
        "authority_sha": envelope.authority,
        "controller_generation_id": envelope.generation,
        "immutable_request_sha256": envelope.envelopeHash,
        "installed_self_sha256": envelope.installerHash,
        "service_identity_sha256": identity,
        "service_claim_sha256": sha256(claimBytes),
        "service_definition_sha256": sha256(definitionBytes),
        "worker_invocations": 1,
        "attempt": 1,
        "retry": false,
        "raw_values": false,
    ])
    let registrationBytes = try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_REGISTRATION_V1",
        "authority_sha": envelope.authority,
        "controller_generation_id": envelope.generation,
        "immutable_request_sha256": envelope.envelopeHash,
        "installed_self_sha256": envelope.installerHash,
        "service_identity_sha256": identity,
        "service_claim_sha256": sha256(claimBytes),
        "service_definition_path_sha256": sha256(Data(definitionPath.utf8)),
        "service_definition_sha256": sha256(definitionBytes),
        "persistence": synthetic
            ? "SYNTHETIC_VERSION_ADDRESSED_ACTIVATION_OWNER"
            : "LAUNCHD_VERSION_ADDRESSED_ACTIVATION_OWNER",
        "status": "REGISTERED",
        "admin_prompt_budget": 1,
        "phase_a_target_writes": 0,
        "attempt": 1,
        "retry": false,
        "raw_values": false,
    ])
    return DurablePhaseBService(
        identity: identity, label: label, claimPath: claimPath, definitionPath: definitionPath,
        activationOwnerDefinitionPath: activationOwnerDefinitionPath,
        invocationPath: invocationPath,
        registrationPath: registrationPath, activationOwnerClaimPath: activationOwnerClaimPath,
        activationOwnerLockPath: activationOwnerLockPath, activationOwnerReadyPath: activationOwnerReadyPath,
        kickstartDecisionPath: kickstartDecisionPath, physicalKickstartPath: physicalKickstartPath,
        workerLockPath: workerLockPath,
        startedPath: startedPath, executingPath: executingPath,
        runClaimPath: runClaimPath, effectEntryPath: effectEntryPath,
        completedPath: completedPath, failedPath: failedPath, stopPartialPath: stopPartialPath,
        settlementPath: settlementPath,
        claimBytes: claimBytes, definitionBytes: definitionBytes,
        activationOwnerDefinitionBytes: activationOwnerDefinitionBytes,
        invocationBytes: invocationBytes,
        registrationBytes: registrationBytes, mode: synthetic ? 0o600 : 0o444, synthetic: synthetic
    )
}

private func writeOrVerifyDurableFile(
    _ path: String, bytes: Data, mode: mode_t, rootOwned: Bool
) throws {
    guard safeAbsolutePath(path) else { try reject() }
    let parentPath = (path as NSString).deletingLastPathComponent
    let leaf = (path as NSString).lastPathComponent
    let chain = try openDirectoryChain(parentPath, create: true)
    defer { for descriptor in chain.reversed() { Darwin.close(descriptor) } }
    let parent = chain.last!
    if let existing = try readExistingAt(parent, leaf) {
        guard existing == bytes, let metadata = try statAt(parent, leaf),
              (metadata.st_mode & S_IFMT) == S_IFREG,
              (metadata.st_mode & 0o777) == mode, metadata.st_nlink == 1,
              (metadata.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try reject() }
        if rootOwned && productionMetadataRequired() {
            guard metadata.st_uid == 0, metadata.st_gid == 0 else { try reject() }
        }
    } else {
        try writeExclusiveAt(parent, leaf, bytes, mode, rootOwned: rootOwned)
#if CI3_SYNTHETIC_TEST
        if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_DURABLE_CRASH_AFTER_EXCLUSIVE_WRITE"] == leaf {
            try reject()
        }
#endif
        let descriptor = leaf.withCString { Darwin.openat(parent, $0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { try reject() }
        defer { Darwin.close(descriptor) }
        let metadata = try fstatValue(descriptor)
        guard (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_nlink == 1,
              (metadata.st_mode & 0o777) == mode,
              (!rootOwned || !productionMetadataRequired() || (metadata.st_uid == 0 && metadata.st_gid == 0)),
              Darwin.fchflags(descriptor, UInt32(UF_IMMUTABLE)) == 0,
              Darwin.fsync(descriptor) == 0, Darwin.fsync(parent) == 0 else { try reject() }
    }
}

private func writeExclusiveDurableFile(
    _ path: String, bytes: Data, mode: mode_t, rootOwned: Bool
) throws {
    guard safeAbsolutePath(path) else { try reject() }
    let parentPath = (path as NSString).deletingLastPathComponent
    let leaf = (path as NSString).lastPathComponent
    let chain = try openDirectoryChain(parentPath, create: true)
    defer { for descriptor in chain.reversed() { Darwin.close(descriptor) } }
    let parent = chain.last!
    guard try readExistingAt(parent, leaf) == nil else { try reject() }
    try writeExclusiveAt(parent, leaf, bytes, mode, rootOwned: rootOwned)
    let descriptor = leaf.withCString { Darwin.openat(parent, $0, O_RDONLY | O_NOFOLLOW) }
    guard descriptor >= 0 else { try reject() }
    defer { Darwin.close(descriptor) }
    let metadata = try fstatValue(descriptor)
    guard (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_nlink == 1,
          (metadata.st_mode & 0o777) == mode,
          (!rootOwned || !productionMetadataRequired() || (metadata.st_uid == 0 && metadata.st_gid == 0)),
          try readDescriptor(descriptor) == bytes,
          Darwin.fchflags(descriptor, UInt32(UF_IMMUTABLE)) == 0,
          Darwin.fsync(descriptor) == 0, Darwin.fsync(parent) == 0 else { try reject() }
}

private func readExactDurableFile(_ path: String, bytes: Data, mode: mode_t, rootOwned: Bool) throws {
    let pinned = try openPinnedFile(path)
    defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
    let descriptorMetadata = try fstatValue(pinned.descriptor)
    guard pinned.before.mode == Int(mode), pinned.before.nlink == 1,
          (descriptorMetadata.st_flags & UInt32(UF_IMMUTABLE)) != 0,
          try readDescriptor(pinned.descriptor) == bytes,
          try physical(descriptorMetadata).identity() == pinned.before.identity() else { try reject() }
    if rootOwned && productionMetadataRequired() {
        guard pinned.before.uid == 0, pinned.before.gid == 0 else { try reject() }
    }
}

#if CI3_SYNTHETIC_TEST
private let durableRegistrationBarrierStages = [
    "CLAIM", "DEFINITION", "INVOCATION", "PRE_BOOTSTRAP", "BOOTSTRAP",
    "POST_BOOTSTRAP", "PRE_REGISTRATION", "REGISTRATION", "POST_KICKSTART",
]

private func durableRegistrationBarrierPath(
    _ service: DurablePhaseBService, stage: String, suffix: String
) -> String {
    let stateRoot = (service.claimPath as NSString).deletingLastPathComponent
    return (stateRoot as NSString).appendingPathComponent(
        "publisher1-durable-registration-\(stage.lowercased()).\(suffix).json"
    )
}

private func awaitSyntheticDurableRegistrationBarrier(
    _ service: DurablePhaseBService, envelope: ImmutableBootstrapEnvelope, stage: String
) throws {
    guard service.synthetic,
          ProcessInfo.processInfo.environment[
            "CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE"
          ] == stage else { return }
    guard durableRegistrationBarrierStages.contains(stage) else { try reject() }
    let prepared = try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_SYNTHETIC_PUBLISHER1_DURABLE_REGISTRATION_BARRIER_V1",
        "authority_sha": envelope.authority,
        "controller_generation_id": envelope.generation,
        "immutable_request_sha256": envelope.envelopeHash,
        "installed_self_sha256": envelope.installerHash,
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "service_definition_sha256": sha256(service.definitionBytes),
        "stage": stage,
        "decision": "PREPARED",
        "raw_values": false,
    ])
    let preparedPath = durableRegistrationBarrierPath(service, stage: stage, suffix: "prepared")
    try writeOrVerifyDurableFile(preparedPath, bytes: prepared, mode: 0o600, rootOwned: false)
    let releasePath = durableRegistrationBarrierPath(service, stage: stage, suffix: "continue")
    let releaseParentPath = (releasePath as NSString).deletingLastPathComponent
    let releaseLeaf = (releasePath as NSString).lastPathComponent
    let releaseChain = try openDirectoryChain(releaseParentPath, create: false)
    defer { for descriptor in releaseChain.reversed() { Darwin.close(descriptor) } }
    let releaseParent = releaseChain.last!
    for _ in 0..<1200 {
        if let bytes = try readExistingAt(releaseParent, releaseLeaf),
           let metadata = try statAt(releaseParent, releaseLeaf) {
            guard let release = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  try canonicalJSON(release) == bytes else { try reject() }
            try exactKeys(release, [
                "schema_version", "purpose", "authority_sha", "controller_generation_id",
                "immutable_request_sha256", "installed_self_sha256", "service_identity_sha256",
                "service_claim_sha256", "service_definition_sha256", "prepared_sha256",
                "stage", "decision", "raw_values",
            ])
            guard try integer(release["schema_version"]) == 1,
                  try string(release["purpose"]) == "CI3_SYNTHETIC_PUBLISHER1_DURABLE_REGISTRATION_BARRIER_RELEASE_V1",
                  try string(release["authority_sha"]) == envelope.authority,
                  try string(release["controller_generation_id"]) == envelope.generation,
                  try string(release["immutable_request_sha256"]) == envelope.envelopeHash,
                  try string(release["installed_self_sha256"]) == envelope.installerHash,
                  try string(release["service_identity_sha256"]) == service.identity,
                  try string(release["service_claim_sha256"]) == sha256(service.claimBytes),
                  try string(release["service_definition_sha256"]) == sha256(service.definitionBytes),
                  try string(release["prepared_sha256"]) == sha256(prepared),
                  try string(release["stage"]) == stage,
                  try string(release["decision"]) == "CONTINUE",
                  try boolean(release["raw_values"]) == false,
                  (metadata.st_mode & S_IFMT) == S_IFREG,
                  (metadata.st_mode & 0o777) == 0o600,
                  metadata.st_nlink == 1, metadata.st_uid == getuid(), metadata.st_gid == getgid()
            else { try reject() }
            return
        }
        Darwin.usleep(25_000)
    }
    try reject()
}

private func killSyntheticSupervisorAtDurableRegistrationBarrier(
    _ service: DurablePhaseBService
) throws {
    guard service.synthetic,
          let stage = ProcessInfo.processInfo.environment[
            "CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE"
          ] else { return }
    guard durableRegistrationBarrierStages.contains(stage) else { try reject() }
    let preparedPath = durableRegistrationBarrierPath(service, stage: stage, suffix: "prepared")
    for _ in 0..<1200 {
        if FileManager.default.fileExists(atPath: preparedPath) {
            Darwin.kill(Darwin.getpid(), SIGKILL)
            try reject()
        }
        Darwin.usleep(25_000)
    }
    try reject()
}

private let durableActivationBarrierStages = ["PRE_SIGNAL", "POST_ACCEPT_PRE_RECEIPT"]

private func awaitSyntheticDurableActivationBarrier(
    _ service: DurablePhaseBService, envelope: ImmutableBootstrapEnvelope, stage: String
) throws {
    guard service.synthetic,
          ProcessInfo.processInfo.environment["CI3_SYNTHETIC_P1_ACTIVATION_BARRIER_STAGE"] == stage
    else { return }
    guard durableActivationBarrierStages.contains(stage) else { try reject() }
    let stateRoot = (service.claimPath as NSString).deletingLastPathComponent
    let slug = stage.lowercased().replacingOccurrences(of: "_", with: "-")
    let preparedPath = (stateRoot as NSString).appendingPathComponent(
        "publisher1-durable-activation-\(slug).prepared.json"
    )
    let releasePath = (stateRoot as NSString).appendingPathComponent(
        "publisher1-durable-activation-\(slug).continue.json"
    )
    let prepared = try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_SYNTHETIC_PUBLISHER1_DURABLE_ACTIVATION_BARRIER_V1",
        "authority_sha": envelope.authority,
        "controller_generation_id": envelope.generation,
        "immutable_request_sha256": envelope.envelopeHash,
        "installed_self_sha256": envelope.installerHash,
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "service_definition_sha256": sha256(service.definitionBytes),
        "stage": stage,
        "decision": "PREPARED",
        "raw_values": false,
    ])
    try writeOrVerifyDurableFile(preparedPath, bytes: prepared, mode: 0o600, rootOwned: false)
    for _ in 0..<1200 {
        if FileManager.default.fileExists(atPath: releasePath) {
            let pinned = try openPinnedFile(releasePath)
            defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
            let bytes = try readDescriptor(pinned.descriptor)
            guard let release = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  try canonicalJSON(release) == bytes else { try reject() }
            try exactKeys(release, [
                "schema_version", "purpose", "authority_sha", "controller_generation_id",
                "immutable_request_sha256", "installed_self_sha256", "service_identity_sha256",
                "service_claim_sha256", "service_definition_sha256", "prepared_sha256",
                "stage", "decision", "raw_values",
            ])
            guard try integer(release["schema_version"]) == 1,
                  try string(release["purpose"]) == "CI3_SYNTHETIC_PUBLISHER1_DURABLE_ACTIVATION_BARRIER_RELEASE_V1",
                  try string(release["authority_sha"]) == envelope.authority,
                  try string(release["controller_generation_id"]) == envelope.generation,
                  try string(release["immutable_request_sha256"]) == envelope.envelopeHash,
                  try string(release["installed_self_sha256"]) == envelope.installerHash,
                  try string(release["service_identity_sha256"]) == service.identity,
                  try string(release["service_claim_sha256"]) == sha256(service.claimBytes),
                  try string(release["service_definition_sha256"]) == sha256(service.definitionBytes),
                  try string(release["prepared_sha256"]) == sha256(prepared),
                  try string(release["stage"]) == stage,
                  try string(release["decision"]) == "CONTINUE",
                  try boolean(release["raw_values"]) == false,
                  pinned.before.mode == 0o600, pinned.before.nlink == 1,
                  pinned.before.uid == Int(getuid()), pinned.before.gid == Int(getgid())
            else { try reject() }
            return
        }
        Darwin.usleep(25_000)
    }
    try reject()
}

private let durableWorkerBarrierStages = [
    "RUN_CLAIM", "PRE_EFFECT_ENTRY", "POST_EFFECT_ENTRY", "PRE_TERMINAL",
]

private func awaitSyntheticDurableWorkerBarrier(
    _ service: DurablePhaseBService, envelope: ImmutableBootstrapEnvelope, stage: String
) throws {
    guard service.synthetic,
          ProcessInfo.processInfo.environment["CI3_SYNTHETIC_P1_WORKER_BARRIER_STAGE"] == stage
    else { return }
    guard durableWorkerBarrierStages.contains(stage) else { try reject() }
    let stateRoot = (service.claimPath as NSString).deletingLastPathComponent
    let slug = stage.lowercased().replacingOccurrences(of: "_", with: "-")
    let preparedPath = (stateRoot as NSString).appendingPathComponent(
        "publisher1-durable-worker-\(slug).prepared.json"
    )
    let releasePath = (stateRoot as NSString).appendingPathComponent(
        "publisher1-durable-worker-\(slug).continue.json"
    )
    let prepared = try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_SYNTHETIC_PUBLISHER1_DURABLE_WORKER_BARRIER_V1",
        "authority_sha": envelope.authority,
        "controller_generation_id": envelope.generation,
        "immutable_request_sha256": envelope.envelopeHash,
        "installed_self_sha256": envelope.installerHash,
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "service_definition_sha256": sha256(service.definitionBytes),
        "stage": stage,
        "decision": "PREPARED",
        "raw_values": false,
    ])
    try writeOrVerifyDurableFile(preparedPath, bytes: prepared, mode: 0o600, rootOwned: false)
    for _ in 0..<1200 {
        if FileManager.default.fileExists(atPath: releasePath) {
            let pinned = try openPinnedFile(releasePath)
            defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
            let bytes = try readDescriptor(pinned.descriptor)
            guard let release = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  try canonicalJSON(release) == bytes else { try reject() }
            try exactKeys(release, [
                "schema_version", "purpose", "authority_sha", "controller_generation_id",
                "immutable_request_sha256", "installed_self_sha256", "service_identity_sha256",
                "service_claim_sha256", "service_definition_sha256", "prepared_sha256",
                "stage", "decision", "raw_values",
            ])
            guard try integer(release["schema_version"]) == 1,
                  try string(release["purpose"]) == "CI3_SYNTHETIC_PUBLISHER1_DURABLE_WORKER_BARRIER_RELEASE_V1",
                  try string(release["authority_sha"]) == envelope.authority,
                  try string(release["controller_generation_id"]) == envelope.generation,
                  try string(release["immutable_request_sha256"]) == envelope.envelopeHash,
                  try string(release["installed_self_sha256"]) == envelope.installerHash,
                  try string(release["service_identity_sha256"]) == service.identity,
                  try string(release["service_claim_sha256"]) == sha256(service.claimBytes),
                  try string(release["service_definition_sha256"]) == sha256(service.definitionBytes),
                  try string(release["prepared_sha256"]) == sha256(prepared),
                  try string(release["stage"]) == stage,
                  try string(release["decision"]) == "CONTINUE",
                  try boolean(release["raw_values"]) == false,
                  pinned.before.mode == 0o600, pinned.before.nlink == 1,
                  pinned.before.uid == Int(getuid()), pinned.before.gid == Int(getgid())
            else { try reject() }
            return
        }
        Darwin.usleep(25_000)
    }
    try reject()
}
#endif

#if CI3_SYNTHETIC_TEST
private func runSyntheticDurableControlProbe(_ arguments: [String]) throws {
    guard arguments.count == 3, arguments[0] == "--synthetic-durable-control-probe",
          safeAbsolutePath(arguments[1]), let bytes = Data(base64Encoded: arguments[2]),
          !bytes.isEmpty else { try reject() }
    try writeOrVerifyDurableFile(arguments[1], bytes: bytes, mode: 0o600, rootOwned: false)
    try readExactDurableFile(arguments[1], bytes: bytes, mode: 0o600, rootOwned: false)
    print("CI3_SYNTHETIC_DURABLE_CONTROL_PROBE PASS raw_values=false")
}
#endif

private func durablePhaseBMarker(
    _ service: DurablePhaseBService, purpose: String, terminalState: String
) throws -> Data {
    try canonicalJSON([
        "schema_version": 1,
        "purpose": purpose,
        "authority_sha": try string((try JSONSerialization.jsonObject(with: service.claimBytes) as? [String: Any])?["authority_sha"]),
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "service_definition_sha256": sha256(service.definitionBytes),
        "terminal_state": terminalState,
        "attempt": 1,
        "retry": false,
        "raw_values": false,
    ])
}

private func waitForDurableRegistration(_ service: DurablePhaseBService) throws {
    for _ in 0..<1200 {
        do {
            try readExactDurableFile(
                service.registrationPath, bytes: service.registrationBytes,
                mode: service.mode, rootOwned: !service.synthetic
            )
            return
        } catch {
            Darwin.usleep(25_000)
        }
    }
    try reject()
}

private enum DurablePhaseBTerminalState {
    case open
    case completed
    case failed
}

private func durablePhaseBTerminalState(_ service: DurablePhaseBService) throws -> DurablePhaseBTerminalState {
    let completed = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_COMPLETED_V1", terminalState: "PHASE_B_SETTLED"
    )
    let failed = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_FAILED_V1", terminalState: "STOP_PRE_AUTHORITY"
    )
    let completedExists = FileManager.default.fileExists(atPath: service.completedPath)
    let failedExists = FileManager.default.fileExists(atPath: service.failedPath)
    guard !(completedExists && failedExists) else { try reject() }
    if completedExists {
        try readExactDurableFile(
            service.completedPath, bytes: completed, mode: service.mode, rootOwned: !service.synthetic
        )
        return .completed
    }
    if failedExists {
        try readExactDurableFile(
            service.failedPath, bytes: failed, mode: service.mode, rootOwned: !service.synthetic
        )
        return .failed
    }
    return .open
}

private func settleDurablePhaseBService(_ service: DurablePhaseBService) throws {
    let settled = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_SERVICE_SETTLED_V1",
        terminalState: "TERMINAL_DISABLED"
    )
    let alreadySettled = FileManager.default.fileExists(atPath: service.settlementPath)
    try writeOrVerifyDurableFile(
        service.settlementPath, bytes: settled, mode: service.mode, rootOwned: !service.synthetic
    )
    if service.synthetic || alreadySettled { return }
    let launchctl = Process()
    launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    launchctl.arguments = ["bootout", "system/\(service.label)"]
    launchctl.standardInput = FileHandle.nullDevice
    launchctl.standardOutput = FileHandle.nullDevice
    launchctl.standardError = FileHandle.nullDevice
    try launchctl.run()
    launchctl.waitUntilExit()
    guard launchctl.terminationReason == .exit, launchctl.terminationStatus == 0 else { try reject() }
}

private func launchctlServiceIsLoaded(_ label: String) throws -> Bool {
    let probe = Process()
    probe.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    probe.arguments = ["print", "system/\(label)"]
    probe.standardInput = FileHandle.nullDevice
    probe.standardOutput = FileHandle.nullDevice
    probe.standardError = FileHandle.nullDevice
    try probe.run()
    probe.waitUntilExit()
    guard probe.terminationReason == .exit else { try reject() }
    return probe.terminationStatus == 0
}

private func durableKickstartDecision(_ service: DurablePhaseBService) throws -> Data {
    let ownerClaim = try durableActivationOwnerClaim(service)
    let ownerReady = try durableActivationOwnerReady(service)
    return try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_KICKSTART_DECISION_V1",
        "authority_sha": try string((try JSONSerialization.jsonObject(with: service.claimBytes) as? [String: Any])?["authority_sha"]),
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "service_definition_sha256": sha256(service.definitionBytes),
        "activation_owner_claim_sha256": sha256(ownerClaim),
        "activation_owner_ready_sha256": sha256(ownerReady),
        "state": "KICKSTART_DECIDED",
        "kickstart_invocations": 1,
        "attempt": 1,
        "retry": false,
        "raw_values": false,
    ])
}

private func durableActivationOwnerClaim(_ service: DurablePhaseBService) throws -> Data {
    try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_ACTIVATION_OWNER_V1",
        "authority_sha": try string((try JSONSerialization.jsonObject(with: service.claimBytes) as? [String: Any])?["authority_sha"]),
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "service_definition_sha256": sha256(service.definitionBytes),
        "activation_owner_definition_sha256": sha256(service.activationOwnerDefinitionBytes),
        "activation_owner_kind": "VERSION_ADDRESSED_PERSISTENT_ACTIVATION_OWNER",
        "kickstart_budget": 1,
        "retry": false,
        "raw_values": false,
    ])
}

private func durableActivationOwnerLock(_ service: DurablePhaseBService) throws -> Data {
    try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_ACTIVATION_OWNER_LOCK_V1",
        "authority_sha": try string((try JSONSerialization.jsonObject(with: service.claimBytes) as? [String: Any])?["authority_sha"]),
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "activation_owner_claim_sha256": sha256(try durableActivationOwnerClaim(service)),
        "terminal_state": "VERSION_BOUND_OWNER_LOCK",
        "retry": false,
        "raw_values": false,
    ])
}

private func durableActivationOwnerReady(_ service: DurablePhaseBService) throws -> Data {
    try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_ACTIVATION_OWNER_READY_V1",
        "authority_sha": try string((try JSONSerialization.jsonObject(with: service.claimBytes) as? [String: Any])?["authority_sha"]),
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "activation_owner_claim_sha256": sha256(try durableActivationOwnerClaim(service)),
        "activation_owner_definition_sha256": sha256(service.activationOwnerDefinitionBytes),
        "state": "OWNER_READY_BEFORE_EFFECT_AUTHORIZATION",
        "activation_owner_launches": 1,
        "retry": false,
        "raw_values": false,
    ])
}

private func durablePhysicalKickstart(_ service: DurablePhaseBService) throws -> Data {
    try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_PHYSICAL_KICKSTART_V1",
        "authority_sha": try string((try JSONSerialization.jsonObject(with: service.claimBytes) as? [String: Any])?["authority_sha"]),
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "activation_owner_claim_sha256": sha256(try durableActivationOwnerClaim(service)),
        "activation_signal_sha256": sha256(try durableKickstartDecision(service)),
        "state": "PHYSICAL_KICKSTART_ACCEPTED",
        "executable_kickstart_invocations": 1,
        "retry": false,
        "raw_values": false,
    ])
}

private func durableWorkerLaunchPath(_ service: DurablePhaseBService, sequence: Int) -> String {
    let stateRoot = (service.claimPath as NSString).deletingLastPathComponent
    return (stateRoot as NSString).appendingPathComponent(
        "publisher1-durable-phase-b.worker-launch-\(sequence).json"
    )
}

private func durableWorkerLaunchBytes(
    _ service: DurablePhaseBService, sequence: Int
) throws -> Data {
    try canonicalJSON([
        "schema_version": 1,
        "purpose": "CI3_PUBLISHER1_DURABLE_PHASE_B_WORKER_LAUNCH_V1",
        "authority_sha": try string((try JSONSerialization.jsonObject(with: service.claimBytes) as? [String: Any])?["authority_sha"]),
        "service_identity_sha256": service.identity,
        "service_claim_sha256": sha256(service.claimBytes),
        "service_definition_sha256": sha256(service.definitionBytes),
        "launch_sequence": sequence,
        "activation": sequence == 1 ? "EXPLICIT_SINGLE_KICKSTART" : "SAME_CONTINUATION_RECOVERY",
        "kickstart_invocations": sequence == 1 ? 1 : 0,
        "effect_executions": 0,
        "attempt": 1,
        "retry": false,
        "raw_values": false,
    ])
}

private func latestDurableWorkerLaunch(
    _ service: DurablePhaseBService
) throws -> Int? {
    var latest: Int? = nil
    for sequence in 1...8 {
        let launchPath = durableWorkerLaunchPath(service, sequence: sequence)
        guard FileManager.default.fileExists(atPath: launchPath) else { break }
        let pinned = try openPinnedFile(launchPath)
        defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
        let bytes = try readDescriptor(pinned.descriptor)
        guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              try canonicalJSON(value) == bytes else { try reject() }
        try exactKeys(value, [
            "schema_version", "purpose", "authority_sha", "service_identity_sha256",
            "service_claim_sha256", "service_definition_sha256", "launch_sequence",
            "activation", "kickstart_invocations", "effect_executions",
            "attempt", "retry", "raw_values",
        ])
        guard try integer(value["schema_version"]) == 1,
              try string(value["purpose"]) == "CI3_PUBLISHER1_DURABLE_PHASE_B_WORKER_LAUNCH_V1",
              try string(value["service_identity_sha256"]) == service.identity,
              try string(value["service_claim_sha256"]) == sha256(service.claimBytes),
              try string(value["service_definition_sha256"]) == sha256(service.definitionBytes),
              try integer(value["launch_sequence"]) == sequence,
              try string(value["activation"]) == (sequence == 1 ? "EXPLICIT_SINGLE_KICKSTART" : "SAME_CONTINUATION_RECOVERY"),
              try integer(value["kickstart_invocations"]) == (sequence == 1 ? 1 : 0),
              try integer(value["effect_executions"]) == 0,
              try integer(value["attempt"]) == 1,
              try boolean(value["retry"]) == false,
              try boolean(value["raw_values"]) == false,
              pinned.before.mode == Int(service.mode), pinned.before.nlink == 1
        else { try reject() }
        latest = sequence
    }
    return latest
}

private func durableWorkerLockBytes(_ service: DurablePhaseBService) throws -> Data {
    try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_WORKER_LOCK_V1",
        terminalState: "VERSION_BOUND_LOCK"
    )
}

private func durableWorkerLockIsHeld(_ service: DurablePhaseBService) throws -> Bool {
    let pinned = try openPinnedFile(service.workerLockPath)
    defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
    let expected = try durableWorkerLockBytes(service)
    let metadata = try fstatValue(pinned.descriptor)
    guard try readDescriptor(pinned.descriptor) == expected,
          (metadata.st_mode & S_IFMT) == S_IFREG,
          (metadata.st_mode & 0o777) == service.mode, metadata.st_nlink == 1,
          (metadata.st_flags & UInt32(UF_IMMUTABLE)) != 0
    else { try reject() }
    if ci3Flock(pinned.descriptor, LOCK_EX | LOCK_NB) == 0 {
        guard ci3Flock(pinned.descriptor, LOCK_UN) == 0 else { try reject() }
        return false
    }
    guard errno == EWOULDBLOCK else { try reject() }
    return true
}

private func durableStopPartial(_ service: DurablePhaseBService) throws -> Data {
    try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_STOP_PARTIAL_V1",
        terminalState: "EFFECT_DECISION_PRESENT_NO_REPLAY"
    )
}

private func runDurablePhaseBWorker(_ arguments: [String]) throws {
    guard arguments.count == 5, arguments[0] == "--durable-immutable-bootstrap-phase-b",
          safeAbsolutePath(arguments[1]), isHex(arguments[2]), safeAbsolutePath(arguments[3]),
          isHex(arguments[4]) else { try reject() }
    let envelope = try parseImmutableBootstrapEnvelope(
        ["--immutable-bootstrap-phase-b", arguments[1], arguments[2]],
        phase: "--immutable-bootstrap-phase-b"
    )
    let installedPath = try verifyImmutableInstallerTree(envelope)
    let executablePath = try currentExecutablePath()
    guard executablePath == URL(fileURLWithPath: installedPath).resolvingSymlinksInPath().path else { try reject() }
    let artifactRoot = try syntheticPhaseBContinuationRoot(envelope)
    let service = try durablePhaseBService(envelope, installedPath: installedPath, artifactRoot: artifactRoot)
    guard arguments[3] == service.claimPath, arguments[4] == sha256(service.claimBytes) else { try reject() }
    let workerLock = try openPinnedFile(service.workerLockPath)
    defer {
        _ = ci3Flock(workerLock.descriptor, LOCK_UN)
        Darwin.close(workerLock.descriptor)
        Darwin.close(workerLock.parent)
    }
    let workerLockMetadata = try fstatValue(workerLock.descriptor)
    guard try readDescriptor(workerLock.descriptor) == durableWorkerLockBytes(service),
          (workerLockMetadata.st_mode & S_IFMT) == S_IFREG,
          (workerLockMetadata.st_mode & 0o777) == service.mode,
          workerLockMetadata.st_nlink == 1,
          (workerLockMetadata.st_flags & UInt32(UF_IMMUTABLE)) != 0,
          ci3Flock(workerLock.descriptor, LOCK_EX | LOCK_NB) == 0
    else { try reject() }
    switch try durablePhaseBTerminalState(service) {
    case .completed, .failed:
        try settleDurablePhaseBService(service)
        fputs("TERMINAL_ALREADY_SETTLED\n", stderr)
        return
    case .open:
        break
    }
    try readExactDurableFile(service.claimPath, bytes: service.claimBytes, mode: service.mode, rootOwned: !service.synthetic)
    try readExactDurableFile(service.definitionPath, bytes: service.definitionBytes, mode: service.mode, rootOwned: !service.synthetic)
    try readExactDurableFile(
        service.invocationPath, bytes: service.invocationBytes,
        mode: service.mode, rootOwned: !service.synthetic
    )
    try waitForDurableRegistration(service)
    let runClaim = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_RUN_CLAIM_V1", terminalState: "CLAIMED"
    )
    try writeOrVerifyDurableFile(
        service.runClaimPath, bytes: runClaim, mode: service.mode, rootOwned: !service.synthetic
    )
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableWorkerBarrier(service, envelope: envelope, stage: "RUN_CLAIM")
#endif
    let started = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_STARTED_V1", terminalState: "RUNNING"
    )
    try writeOrVerifyDurableFile(
        service.startedPath, bytes: started, mode: service.mode, rootOwned: !service.synthetic
    )
    do {
        try awaitSyntheticPhaseBContinuation(artifactRoot, envelope: envelope)
        let executing = try durablePhaseBMarker(
            service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_EXECUTING_V1",
            terminalState: "PHASE_B_EXECUTING"
        )
        try writeOrVerifyDurableFile(
            service.executingPath, bytes: executing, mode: service.mode, rootOwned: !service.synthetic
        )
#if CI3_SYNTHETIC_TEST
        try awaitSyntheticDurableWorkerBarrier(service, envelope: envelope, stage: "PRE_EFFECT_ENTRY")
#endif
        let effectEntry = try durablePhaseBMarker(
            service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_EFFECT_ENTRY_V1",
            terminalState: "EFFECT_ENTERED"
        )
        try writeExclusiveDurableFile(
            service.effectEntryPath, bytes: effectEntry, mode: service.mode, rootOwned: !service.synthetic
        )
#if CI3_SYNTHETIC_TEST
        try awaitSyntheticDurableWorkerBarrier(service, envelope: envelope, stage: "POST_EFFECT_ENTRY")
#endif
        try publishImmutablePhaseB(["--immutable-bootstrap-phase-b", envelope.envelopePath, envelope.envelopeHash])
#if CI3_SYNTHETIC_TEST
        try awaitSyntheticDurableWorkerBarrier(service, envelope: envelope, stage: "PRE_TERMINAL")
#endif
        let completed = try durablePhaseBMarker(
            service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_COMPLETED_V1", terminalState: "PHASE_B_SETTLED"
        )
        try writeOrVerifyDurableFile(
            service.completedPath, bytes: completed, mode: service.mode, rootOwned: !service.synthetic
        )
    } catch {
        if FileManager.default.fileExists(atPath: service.effectEntryPath) {
            let stopPartial = try durableStopPartial(service)
            try? writeOrVerifyDurableFile(
                service.stopPartialPath, bytes: stopPartial,
                mode: service.mode, rootOwned: !service.synthetic
            )
        }
        let failed = try durablePhaseBMarker(
            service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_FAILED_V1", terminalState: "STOP_PRE_AUTHORITY"
        )
        try? writeOrVerifyDurableFile(
            service.failedPath, bytes: failed, mode: service.mode, rootOwned: !service.synthetic
        )
        try? settleDurablePhaseBService(service)
        throw error
    }
    try settleDurablePhaseBService(service)
}

private func spawnDurablePhaseBWorker(
    _ service: DurablePhaseBService, installedPath: String,
    envelope: ImmutableBootstrapEnvelope, sequence: Int
) throws -> Process {
    guard sequence >= 1 && sequence <= 8 else { try reject() }
    let child = Process()
    if sequence > 1 {
        child.executableURL = URL(fileURLWithPath: installedPath)
        child.arguments = [
            "--durable-immutable-bootstrap-phase-b", envelope.envelopePath, envelope.envelopeHash,
            service.claimPath, sha256(service.claimBytes),
        ]
    } else if service.synthetic {
        child.executableURL = URL(fileURLWithPath: installedPath)
        child.arguments = [
            "--synthetic-durable-phase-b-kickstart", envelope.envelopePath, envelope.envelopeHash,
            service.claimPath, sha256(service.claimBytes),
        ]
    } else {
        child.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        child.arguments = ["kickstart", "system/\(service.label)"]
    }
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    try child.run()
    if sequence > 1 {
        let receipt = try durableWorkerLaunchBytes(service, sequence: sequence)
        try writeExclusiveDurableFile(
            durableWorkerLaunchPath(service, sequence: sequence), bytes: receipt,
            mode: service.mode, rootOwned: !service.synthetic
        )
    }
    return child
}

#if CI3_SYNTHETIC_TEST
private func runSyntheticDurablePhaseBKickstart(_ arguments: [String]) throws {
    guard arguments.count == 5, arguments[0] == "--synthetic-durable-phase-b-kickstart",
          safeAbsolutePath(arguments[1]), isHex(arguments[2]), safeAbsolutePath(arguments[3]),
          isHex(arguments[4]) else { try reject() }
    let envelope = try parseImmutableBootstrapEnvelope(
        ["--immutable-bootstrap-phase-b", arguments[1], arguments[2]],
        phase: "--immutable-bootstrap-phase-b"
    )
    let installedPath = try verifyImmutableInstallerTree(envelope)
    let executablePath = try currentExecutablePath()
    guard executablePath == URL(fileURLWithPath: installedPath).resolvingSymlinksInPath().path
    else { try reject() }
    let artifactRoot = try syntheticPhaseBContinuationRoot(envelope)
    guard artifactRoot != nil else { try reject() }
    let service = try durablePhaseBService(
        envelope, installedPath: installedPath, artifactRoot: artifactRoot
    )
    guard arguments[3] == service.claimPath, arguments[4] == sha256(service.claimBytes)
    else { try reject() }
    try readExactDurableFile(
        service.kickstartDecisionPath, bytes: try durableKickstartDecision(service),
        mode: service.mode, rootOwned: false
    )
    let worker = Process()
    worker.executableURL = URL(fileURLWithPath: installedPath)
    worker.arguments = [
        "--durable-immutable-bootstrap-phase-b", envelope.envelopePath, envelope.envelopeHash,
        service.claimPath, sha256(service.claimBytes),
    ]
    worker.standardInput = FileHandle.nullDevice
    worker.standardOutput = FileHandle.nullDevice
    worker.standardError = FileHandle.nullDevice
    try worker.run()
    try writeExclusiveDurableFile(
        service.physicalKickstartPath, bytes: try durablePhysicalKickstart(service),
        mode: service.mode, rootOwned: false
    )
}
#endif

private func waitForDurableActivationOwnerFoundation(_ service: DurablePhaseBService) throws {
    let ownerClaim = try durableActivationOwnerClaim(service)
    let ownerLock = try durableActivationOwnerLock(service)
    for _ in 0..<1200 {
        do {
            try readExactDurableFile(
                service.claimPath, bytes: service.claimBytes,
                mode: service.mode, rootOwned: !service.synthetic
            )
            try readExactDurableFile(
                service.definitionPath, bytes: service.definitionBytes,
                mode: service.mode, rootOwned: !service.synthetic
            )
            try readExactDurableFile(
                service.activationOwnerDefinitionPath, bytes: service.activationOwnerDefinitionBytes,
                mode: service.mode, rootOwned: !service.synthetic
            )
            try readExactDurableFile(
                service.registrationPath, bytes: service.registrationBytes,
                mode: service.mode, rootOwned: !service.synthetic
            )
            try readExactDurableFile(
                service.activationOwnerClaimPath, bytes: ownerClaim,
                mode: service.mode, rootOwned: !service.synthetic
            )
            try readExactDurableFile(
                service.activationOwnerLockPath, bytes: ownerLock,
                mode: service.mode, rootOwned: !service.synthetic
            )
            try readExactDurableFile(
                service.workerLockPath, bytes: try durableWorkerLockBytes(service),
                mode: service.mode, rootOwned: !service.synthetic
            )
            return
        } catch {
            Darwin.usleep(25_000)
        }
    }
    try reject()
}

private func waitForDurableActivationSignal(_ service: DurablePhaseBService) throws {
    let decision = try durableKickstartDecision(service)
    for _ in 0..<1200 {
        do {
            try readExactDurableFile(
                service.kickstartDecisionPath, bytes: decision,
                mode: service.mode, rootOwned: !service.synthetic
            )
            return
        } catch {
            Darwin.usleep(25_000)
        }
    }
    try reject()
}

private func waitForDurableActivationOwnerReady(_ service: DurablePhaseBService) throws {
    let ready = try durableActivationOwnerReady(service)
    for _ in 0..<1200 {
        do {
            try readExactDurableFile(
                service.activationOwnerReadyPath, bytes: ready,
                mode: service.mode, rootOwned: !service.synthetic
            )
            return
        } catch {
            Darwin.usleep(25_000)
        }
    }
    try reject()
}

private func waitForInitialDurableWorkerLaunch(_ service: DurablePhaseBService) throws {
    let launchPath = durableWorkerLaunchPath(service, sequence: 1)
    let launch = try durableWorkerLaunchBytes(service, sequence: 1)
    for _ in 0..<1200 {
        do {
            try readExactDurableFile(
                launchPath, bytes: launch, mode: service.mode, rootOwned: !service.synthetic
            )
            try readExactDurableFile(
                service.physicalKickstartPath, bytes: try durablePhysicalKickstart(service),
                mode: service.mode, rootOwned: !service.synthetic
            )
            return
        } catch {
            Darwin.usleep(25_000)
        }
    }
    try reject()
}

private func waitForDurablePhaseBTerminal(_ service: DurablePhaseBService) throws {
    for _ in 0..<1200 {
        switch try durablePhaseBTerminalState(service) {
        case .completed, .failed:
            return
        case .open:
            Darwin.usleep(25_000)
        }
    }
    try reject()
}

private func superviseDurablePhaseBWorker(
    _ service: DurablePhaseBService, installedPath: String, envelope: ImmutableBootstrapEnvelope
) throws {
    switch try durablePhaseBTerminalState(service) {
    case .completed, .failed:
        try settleDurablePhaseBService(service)
        return
    case .open:
        break
    }
    var child: Process? = nil
    if try latestDurableWorkerLaunch(service) == nil {
        if FileManager.default.fileExists(atPath: service.physicalKickstartPath) {
            try readExactDurableFile(
                service.physicalKickstartPath, bytes: try durablePhysicalKickstart(service),
                mode: service.mode, rootOwned: !service.synthetic
            )
            try reject()
        }
        child = try spawnDurablePhaseBWorker(
            service, installedPath: installedPath, envelope: envelope, sequence: 1
        )
        child?.waitUntilExit()
        guard child?.terminationReason == .exit, child?.terminationStatus == 0 else { try reject() }
        child = nil
        if !service.synthetic {
            try writeExclusiveDurableFile(
                service.physicalKickstartPath, bytes: try durablePhysicalKickstart(service),
                mode: service.mode, rootOwned: true
            )
        }
#if CI3_SYNTHETIC_TEST
        try awaitSyntheticDurableActivationBarrier(
            service, envelope: envelope, stage: "POST_ACCEPT_PRE_RECEIPT"
        )
#endif
        try writeExclusiveDurableFile(
            durableWorkerLaunchPath(service, sequence: 1),
            bytes: try durableWorkerLaunchBytes(service, sequence: 1),
            mode: service.mode, rootOwned: !service.synthetic
        )
    }
    try readExactDurableFile(
        service.physicalKickstartPath, bytes: try durablePhysicalKickstart(service),
        mode: service.mode, rootOwned: !service.synthetic
    )
    let runClaim = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_RUN_CLAIM_V1", terminalState: "CLAIMED"
    )
    let effectEntry = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_EFFECT_ENTRY_V1", terminalState: "EFFECT_ENTERED"
    )
    var startupGraceObservations = 0
    for _ in 0..<1200 {
        switch try durablePhaseBTerminalState(service) {
        case .completed, .failed:
            return
        case .open:
            break
        }
        if let child, child.isRunning {
            Darwin.usleep(25_000)
            continue
        }
        if child != nil {
            child?.waitUntilExit()
            child = nil
        }
        guard let observedLaunch = try latestDurableWorkerLaunch(service) else { try reject() }
        if try durableWorkerLockIsHeld(service) {
            startupGraceObservations = 0
            Darwin.usleep(25_000)
            continue
        }
        if FileManager.default.fileExists(atPath: service.effectEntryPath) {
            try readExactDurableFile(
                service.effectEntryPath, bytes: effectEntry,
                mode: service.mode, rootOwned: !service.synthetic
            )
            try settleDurablePhaseBStopPartial(service)
            return
        }
        if FileManager.default.fileExists(atPath: service.runClaimPath) {
            startupGraceObservations = 0
            try readExactDurableFile(
                service.runClaimPath, bytes: runClaim,
                mode: service.mode, rootOwned: !service.synthetic
            )
        } else if startupGraceObservations < 40 {
            startupGraceObservations += 1
            Darwin.usleep(25_000)
            continue
        }
        let nextSequence = observedLaunch + 1
        child = try spawnDurablePhaseBWorker(
            service, installedPath: installedPath, envelope: envelope, sequence: nextSequence
        )
        startupGraceObservations = 0
    }
    try reject()
}

private func runDurablePhaseBActivationOwner(_ arguments: [String]) throws {
    guard arguments.count == 5, arguments[0] == "--durable-immutable-bootstrap-activation-owner",
          safeAbsolutePath(arguments[1]), isHex(arguments[2]), safeAbsolutePath(arguments[3]),
          isHex(arguments[4]) else { try reject() }
    let envelope = try parseImmutableBootstrapEnvelope(
        ["--immutable-bootstrap-phase-b", arguments[1], arguments[2]],
        phase: "--immutable-bootstrap-phase-b"
    )
    let installedPath = try verifyImmutableInstallerTree(envelope)
    let executablePath = try currentExecutablePath()
    guard executablePath == URL(fileURLWithPath: installedPath).resolvingSymlinksInPath().path
    else { try reject() }
    let artifactRoot = try syntheticPhaseBContinuationRoot(envelope)
    let service = try durablePhaseBService(
        envelope, installedPath: installedPath, artifactRoot: artifactRoot
    )
    guard arguments[3] == service.claimPath, arguments[4] == sha256(service.claimBytes)
    else { try reject() }
    try waitForDurableActivationOwnerFoundation(service)
    let ownerLock = try openPinnedFile(service.activationOwnerLockPath)
    defer {
        _ = ci3Flock(ownerLock.descriptor, LOCK_UN)
        Darwin.close(ownerLock.descriptor)
        Darwin.close(ownerLock.parent)
    }
    let ownerLockMetadata = try fstatValue(ownerLock.descriptor)
    guard try readDescriptor(ownerLock.descriptor) == durableActivationOwnerLock(service),
          (ownerLockMetadata.st_mode & S_IFMT) == S_IFREG,
          (ownerLockMetadata.st_mode & 0o777) == service.mode,
          ownerLockMetadata.st_nlink == 1,
          (ownerLockMetadata.st_flags & UInt32(UF_IMMUTABLE)) != 0,
          ci3Flock(ownerLock.descriptor, LOCK_EX | LOCK_NB) == 0
    else { try reject() }
    try writeOrVerifyDurableFile(
        service.activationOwnerReadyPath, bytes: try durableActivationOwnerReady(service),
        mode: service.mode, rootOwned: !service.synthetic
    )
    try waitForDurableActivationSignal(service)
    try superviseDurablePhaseBWorker(service, installedPath: installedPath, envelope: envelope)
}

private func settleDurablePhaseBStopPartial(_ service: DurablePhaseBService) throws {
    let effectEntry = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_EFFECT_ENTRY_V1",
        terminalState: "EFFECT_ENTERED"
    )
    try readExactDurableFile(
        service.effectEntryPath, bytes: effectEntry,
        mode: service.mode, rootOwned: !service.synthetic
    )
    try writeOrVerifyDurableFile(
        service.stopPartialPath, bytes: try durableStopPartial(service),
        mode: service.mode, rootOwned: !service.synthetic
    )
    let failed = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_FAILED_V1",
        terminalState: "STOP_PRE_AUTHORITY"
    )
    try writeOrVerifyDurableFile(
        service.failedPath, bytes: failed, mode: service.mode, rootOwned: !service.synthetic
    )
    try settleDurablePhaseBService(service)
}

private func registerDurablePhaseBService(
    _ installedPath: String, envelope: ImmutableBootstrapEnvelope, artifactRoot: String?
) throws -> DurablePhaseBService {
    let service = try durablePhaseBService(envelope, installedPath: installedPath, artifactRoot: artifactRoot)
    try writeOrVerifyDurableFile(
        service.claimPath, bytes: service.claimBytes, mode: service.mode, rootOwned: !service.synthetic
    )
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableRegistrationBarrier(service, envelope: envelope, stage: "CLAIM")
#endif
    try writeOrVerifyDurableFile(
        service.definitionPath, bytes: service.definitionBytes, mode: service.mode, rootOwned: !service.synthetic
    )
    try writeOrVerifyDurableFile(
        service.activationOwnerDefinitionPath, bytes: service.activationOwnerDefinitionBytes,
        mode: service.mode, rootOwned: !service.synthetic
    )
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableRegistrationBarrier(service, envelope: envelope, stage: "DEFINITION")
#endif
    try writeOrVerifyDurableFile(
        service.invocationPath, bytes: service.invocationBytes,
        mode: service.mode, rootOwned: !service.synthetic
    )
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableRegistrationBarrier(service, envelope: envelope, stage: "INVOCATION")
    try awaitSyntheticDurableRegistrationBarrier(service, envelope: envelope, stage: "PRE_BOOTSTRAP")
#endif
    var bootstrap: Process? = nil
    let workerServiceAlreadyLoaded = service.synthetic ? false : try launchctlServiceIsLoaded(service.label)
    if !service.synthetic && !workerServiceAlreadyLoaded {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        child.arguments = ["bootstrap", "system", service.definitionPath]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        bootstrap = child
    }
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableRegistrationBarrier(service, envelope: envelope, stage: "BOOTSTRAP")
#endif
    if let bootstrap {
        bootstrap.waitUntilExit()
        guard bootstrap.terminationReason == .exit, bootstrap.terminationStatus == 0 else { try reject() }
    }
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableRegistrationBarrier(service, envelope: envelope, stage: "POST_BOOTSTRAP")
    try awaitSyntheticDurableRegistrationBarrier(service, envelope: envelope, stage: "PRE_REGISTRATION")
#endif
    try writeOrVerifyDurableFile(
        service.registrationPath, bytes: service.registrationBytes,
        mode: service.mode, rootOwned: !service.synthetic
    )
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableRegistrationBarrier(service, envelope: envelope, stage: "REGISTRATION")
#endif
    try writeOrVerifyDurableFile(
        service.workerLockPath, bytes: try durableWorkerLockBytes(service),
        mode: service.mode, rootOwned: !service.synthetic
    )
    try writeOrVerifyDurableFile(
        service.activationOwnerClaimPath, bytes: try durableActivationOwnerClaim(service),
        mode: service.mode, rootOwned: !service.synthetic
    )
    try writeOrVerifyDurableFile(
        service.activationOwnerLockPath, bytes: try durableActivationOwnerLock(service),
        mode: service.mode, rootOwned: !service.synthetic
    )
    switch try durablePhaseBTerminalState(service) {
    case .completed, .failed:
        return service
    case .open:
        break
    }
    try waitForDurableActivationOwnerReady(service)
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableActivationBarrier(service, envelope: envelope, stage: "PRE_SIGNAL")
#endif
    let kickstartDecision = try durableKickstartDecision(service)
    if FileManager.default.fileExists(atPath: service.kickstartDecisionPath) {
        try readExactDurableFile(
            service.kickstartDecisionPath, bytes: kickstartDecision,
            mode: service.mode, rootOwned: !service.synthetic
        )
    } else {
        try writeExclusiveDurableFile(
            service.kickstartDecisionPath, bytes: kickstartDecision,
            mode: service.mode, rootOwned: !service.synthetic
        )
    }
    try waitForInitialDurableWorkerLaunch(service)
#if CI3_SYNTHETIC_TEST
    try awaitSyntheticDurableRegistrationBarrier(
        service, envelope: envelope, stage: "POST_KICKSTART"
    )
#endif
    try waitForDurablePhaseBTerminal(service)
    return service
}

private func runDurablePhaseBRegistrar(_ arguments: [String]) throws {
    guard arguments.count == 3, arguments[0] == "--durable-immutable-bootstrap-registrar",
          safeAbsolutePath(arguments[1]), isHex(arguments[2]) else { try reject() }
    let envelope = try parseImmutableBootstrapEnvelope(
        ["--immutable-bootstrap-phase-b", arguments[1], arguments[2]],
        phase: "--immutable-bootstrap-phase-b"
    )
    let installedPath = try verifyImmutableInstallerTree(envelope)
    let executablePath = try currentExecutablePath()
    guard executablePath == URL(fileURLWithPath: installedPath).resolvingSymlinksInPath().path else { try reject() }
    let artifactRoot = try syntheticPhaseBContinuationRoot(envelope)
    _ = try registerDurablePhaseBService(installedPath, envelope: envelope, artifactRoot: artifactRoot)
}

private func runDurablePhaseBRegistrarSupervisor(_ arguments: [String]) throws {
    guard arguments.count == 3, arguments[0] == "--durable-immutable-bootstrap-registrar-supervisor",
          safeAbsolutePath(arguments[1]), isHex(arguments[2]) else { try reject() }
    let envelope = try parseImmutableBootstrapEnvelope(
        ["--immutable-bootstrap-phase-b", arguments[1], arguments[2]],
        phase: "--immutable-bootstrap-phase-b"
    )
    let installedPath = try verifyImmutableInstallerTree(envelope)
    let executablePath = try currentExecutablePath()
    guard executablePath == URL(fileURLWithPath: installedPath).resolvingSymlinksInPath().path else { try reject() }
    let artifactRoot = try syntheticPhaseBContinuationRoot(envelope)
    guard artifactRoot != nil else { try reject() }
    let service = try durablePhaseBService(
        envelope, installedPath: installedPath, artifactRoot: artifactRoot
    )
    let activationOwner = Process()
    activationOwner.executableURL = URL(fileURLWithPath: installedPath)
    activationOwner.arguments = [
        "--durable-immutable-bootstrap-activation-owner", envelope.envelopePath, envelope.envelopeHash,
        service.claimPath, sha256(service.claimBytes),
    ]
    activationOwner.standardInput = FileHandle.nullDevice
    activationOwner.standardOutput = FileHandle.nullDevice
    activationOwner.standardError = FileHandle.nullDevice
    try activationOwner.run()
    for _ in 0..<8 {
        let registrar = Process()
        registrar.executableURL = URL(fileURLWithPath: installedPath)
        registrar.arguments = [
            "--durable-immutable-bootstrap-registrar", envelope.envelopePath, envelope.envelopeHash,
        ]
        registrar.standardInput = FileHandle.nullDevice
        registrar.standardOutput = FileHandle.nullDevice
        registrar.standardError = FileHandle.nullDevice
        try registrar.run()
        registrar.waitUntilExit()
        if registrar.terminationReason == .exit && registrar.terminationStatus == 0 {
            activationOwner.waitUntilExit()
            guard activationOwner.terminationReason == .exit,
                  activationOwner.terminationStatus == 0 else { try reject() }
            return
        }
        guard registrar.terminationReason == .uncaughtSignal else { try reject() }
        guard activationOwner.isRunning else { try reject() }
    }
    try reject()
}

private func durablePhaseBRegistrarDefinition(
    label: String, installedPath: String, envelope: ImmutableBootstrapEnvelope
) -> Data {
    let escape: (String) -> String = { value in
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    let registrarLabel = "\(label).registrar"
    let arguments = [
        installedPath, "--durable-immutable-bootstrap-registrar",
        envelope.envelopePath, envelope.envelopeHash,
    ].map { "<string>\(escape($0))</string>" }.joined()
    return Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>Label</key><string>\(escape(registrarLabel))</string><key>ProcessType</key><string>Background</string><key>ProgramArguments</key><array>\(arguments)</array><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict><key>StandardErrorPath</key><string>/dev/null</string><key>StandardInPath</key><string>/dev/null</string><key>StandardOutPath</key><string>/dev/null</string></dict></plist>
    """.utf8)
}

private func spawnDurablePhaseBRegistrar(
    _ installedPath: String, envelope: ImmutableBootstrapEnvelope
) throws {
    let artifactRoot = try syntheticPhaseBContinuationRoot(envelope)
    if artifactRoot != nil {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: installedPath)
        child.arguments = [
            "--durable-immutable-bootstrap-registrar-supervisor", envelope.envelopePath, envelope.envelopeHash,
        ]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        return
    }
    let service = try durablePhaseBService(envelope, installedPath: installedPath, artifactRoot: nil)
    let activationOwnerLabel = "\(service.label).activation-owner"
    try writeOrVerifyDurableFile(
        service.activationOwnerDefinitionPath, bytes: service.activationOwnerDefinitionBytes,
        mode: 0o444, rootOwned: true
    )
    if !(try launchctlServiceIsLoaded(activationOwnerLabel)) {
        let bootstrapOwner = Process()
        bootstrapOwner.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrapOwner.arguments = ["bootstrap", "system", service.activationOwnerDefinitionPath]
        bootstrapOwner.standardInput = FileHandle.nullDevice
        bootstrapOwner.standardOutput = FileHandle.nullDevice
        bootstrapOwner.standardError = FileHandle.nullDevice
        try bootstrapOwner.run()
        bootstrapOwner.waitUntilExit()
        guard bootstrapOwner.terminationReason == .exit,
              bootstrapOwner.terminationStatus == 0 else { try reject() }
    }
    let registrarLabel = "\(service.label).registrar"
    let definitionPath = "/Library/LaunchDaemons/\(registrarLabel).plist"
    let definition = durablePhaseBRegistrarDefinition(
        label: service.label, installedPath: installedPath, envelope: envelope
    )
    try writeOrVerifyDurableFile(definitionPath, bytes: definition, mode: 0o444, rootOwned: true)
    if !(try launchctlServiceIsLoaded(registrarLabel)) {
        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "system", definitionPath]
        bootstrap.standardInput = FileHandle.nullDevice
        bootstrap.standardOutput = FileHandle.nullDevice
        bootstrap.standardError = FileHandle.nullDevice
        try bootstrap.run()
        bootstrap.waitUntilExit()
        guard bootstrap.terminationReason == .exit, bootstrap.terminationStatus == 0 else { try reject() }
    }
    let kickstart = Process()
    kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    kickstart.arguments = ["kickstart", "system/\(registrarLabel)"]
    kickstart.standardInput = FileHandle.nullDevice
    kickstart.standardOutput = FileHandle.nullDevice
    kickstart.standardError = FileHandle.nullDevice
    try kickstart.run()
    kickstart.waitUntilExit()
    guard kickstart.terminationReason == .exit, kickstart.terminationStatus == 0 else { try reject() }
}

private func awaitDurablePhaseBService(_ service: DurablePhaseBService) throws {
#if CI3_SYNTHETIC_TEST
    try killSyntheticSupervisorAtDurableRegistrationBarrier(service)
    if service.synthetic && ProcessInfo.processInfo.environment[
        "CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AFTER_SERVICE_REGISTRATION"
    ] == "1" {
        try waitForDurableRegistration(service)
        Darwin.kill(Darwin.getpid(), SIGKILL)
        try reject()
    }
#endif
    let completed = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_COMPLETED_V1", terminalState: "PHASE_B_SETTLED"
    )
    let failed = try durablePhaseBMarker(
        service, purpose: "CI3_PUBLISHER1_DURABLE_PHASE_B_FAILED_V1", terminalState: "STOP_PRE_AUTHORITY"
    )
    for _ in 0..<1200 {
        do {
            try readExactDurableFile(
                service.completedPath, bytes: completed, mode: service.mode, rootOwned: !service.synthetic
            )
            return
        } catch {}
        do {
            try readExactDurableFile(
                service.failedPath, bytes: failed, mode: service.mode, rootOwned: !service.synthetic
            )
            try reject()
        } catch BootstrapError.rejected {
            if FileManager.default.fileExists(atPath: service.failedPath) { try reject() }
        }
        Darwin.usleep(25_000)
    }
    try reject()
}

private func continueThroughDurablePhaseB(
    _ installedPath: String, envelope: ImmutableBootstrapEnvelope, artifactRoot: String?
) throws {
#if CI3_SYNTHETIC_TEST
    guard artifactRoot != nil else {
        try transferToImmutablePhaseB(installedPath, envelope: envelope)
        return
    }
#endif
    let service = try durablePhaseBService(envelope, installedPath: installedPath, artifactRoot: artifactRoot)
    do {
        try readExactDurableFile(
            service.registrationPath, bytes: service.registrationBytes,
            mode: service.mode, rootOwned: !service.synthetic
        )
    } catch {
        try spawnDurablePhaseBRegistrar(installedPath, envelope: envelope)
    }
    try awaitDurablePhaseBService(service)
}

private func transferToImmutablePhaseB(_ installedPath: String, envelope: ImmutableBootstrapEnvelope) throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: installedPath)
    child.arguments = ["--immutable-bootstrap-phase-b", envelope.envelopePath, envelope.envelopeHash]
    try child.run()
    child.waitUntilExit()
    guard child.terminationReason == .exit, child.terminationStatus == 0 else { try reject() }
}

private func currentExecutablePath() throws -> String {
    // dyld image zero is the loaded Mach-O, independent of argv[0].
    guard let image = dyldImageName(0) else { try reject() }
    let path = String(cString: image)
    guard safeAbsolutePath(path) else { try reject() }
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    return resolved
}

private func boundaryFileObservation(_ record: [String: Any], expectedRole: String?) throws -> (String, String, Physical) {
    let keys = ["path", "path_sha256", "sha256", "uid", "gid", "mode", "nlink", "size",
                "mtime_ns", "dev", "ino", "identity_sha256"] + (expectedRole == nil ? [] : ["role"])
    try exactKeys(record, keys)
    let path = try string(record["path"])
    let observed = Physical(
        uid: try integer(record["uid"]), gid: try integer(record["gid"]), mode: try integer(record["mode"]),
        nlink: try integer(record["nlink"]), size: try integer(record["size"]),
        mtimeNS: try string(record["mtime_ns"]), dev: try string(record["dev"]), ino: try string(record["ino"])
    )
    guard safeAbsolutePath(path), try string(record["path_sha256"]) == sha256(Data(path.utf8)),
          isHex(try string(record["sha256"])), observed.uid > 0, observed.gid > 0,
          observed.mode == 0o600, observed.nlink == 1,
          try string(record["identity_sha256"]) == observed.identity() else { try reject() }
    if let expectedRole { guard try string(record["role"]) == expectedRole else { try reject() } }
    return (path, try string(record["sha256"]), observed)
}

private func validatePrivilegedBoundary(
    _ path: String, expectedHash: String, envelope: ImmutableBootstrapEnvelope
) throws {
    let pinned = try openPinnedFile(path)
    defer { Darwin.close(pinned.descriptor); Darwin.close(pinned.parent) }
    guard pinned.before.mode == 0o600, pinned.before.nlink == 1 else { try reject() }
    let bytes = try readDescriptor(pinned.descriptor)
    let after = try physical(fstatValue(pinned.descriptor))
    var named = stat()
    guard sha256(bytes) == expectedHash, after.identity() == pinned.before.identity(),
          pinned.leaf.withCString({ Darwin.fstatat(pinned.parent, $0, &named, AT_SYMLINK_NOFOLLOW) }) == 0,
          try physical(named).identity() == pinned.before.identity(),
          let boundary = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          try canonicalJSON(boundary) == bytes else { try reject() }
    try exactKeys(boundary, [
        "schema_version", "purpose", "authority_sha", "controller_generation_id",
        "bootstrap_request_path", "bootstrap_request_sha256", "semantic_preflight_receipt_path",
        "semantic_preflight_receipt_sha256", "immutable_request_path", "immutable_request_sha256",
        "descriptor_request", "receiver_root", "receiver_leaves", "status", "target_writes",
        "privilege_prompts", "attempt", "retry", "raw_values",
    ])
    let descriptor = try object(boundary["descriptor_request"])
    let receiver = try object(boundary["receiver_root"])
    let leaves = try array(boundary["receiver_leaves"])
    guard try integer(boundary["schema_version"]) == 1,
          try string(boundary["purpose"]) == "CI3_PUBLISHER1_PRIVILEGED_BOUNDARY_REQUEST_V1",
          try string(boundary["authority_sha"]) == envelope.authority,
          try string(boundary["controller_generation_id"]) == envelope.generation,
          try string(boundary["bootstrap_request_path"]) == envelope.requestPath,
          try string(boundary["bootstrap_request_sha256"]) == envelope.requestHash,
          try string(boundary["semantic_preflight_receipt_path"]) == envelope.preflightPath,
          try string(boundary["semantic_preflight_receipt_sha256"]) == envelope.preflightHash,
          try string(boundary["immutable_request_path"]) == envelope.envelopePath,
          try string(boundary["immutable_request_sha256"]) == envelope.envelopeHash,
          try string(boundary["status"]) == "REOBSERVED_PASS", try integer(boundary["target_writes"]) == 0,
          try integer(boundary["privilege_prompts"]) == 0, try integer(boundary["attempt"]) == 1,
          try boolean(boundary["retry"]) == false, try boolean(boundary["raw_values"]) == false,
          leaves.count == receiverRoles.count else { try reject() }
    let descriptorObservation = try boundaryFileObservation(descriptor, expectedRole: nil)
    let (descriptorBytes, descriptorPhysical) = try boundOwnerFile(
        descriptorObservation.0, expectedHash: descriptorObservation.1,
        expectedIdentity: descriptorObservation.2.identity(), expectedUID: descriptorObservation.2.uid,
        expectedGID: descriptorObservation.2.gid
    )
    guard sha256(descriptorBytes) == descriptorObservation.1,
          descriptorPhysical.identity() == descriptorObservation.2.identity() else { try reject() }
    try exactKeys(receiver, ["path", "path_sha256", "identity_sha256"])
    let receiverPath = try string(receiver["path"])
    guard safeAbsolutePath(receiverPath), try string(receiver["path_sha256"]) == sha256(Data(receiverPath.utf8)) else { try reject() }
    let receiverChain = try openDirectoryChain(receiverPath, create: false)
    defer { for descriptor in receiverChain.reversed() { Darwin.close(descriptor) } }
    guard try physical(fstatValue(receiverChain.last!)).identity() == string(receiver["identity_sha256"]) else { try reject() }
    for (index, record) in leaves.enumerated() {
        let observation = try boundaryFileObservation(record, expectedRole: receiverRoles[index])
        guard observation.0 == (receiverPath as NSString).appendingPathComponent("\(receiverRoles[index]).payload") else { try reject() }
        let (leafBytes, leafPhysical) = try boundOwnerFile(
            observation.0, expectedHash: observation.1, expectedIdentity: observation.2.identity(),
            expectedUID: observation.2.uid, expectedGID: observation.2.gid
        )
        guard sha256(leafBytes) == observation.1, leafPhysical.identity() == observation.2.identity() else { try reject() }
    }
}

private func bootstrapSelectedPhaseA(_ envelope: ImmutableBootstrapEnvelope, candidateBytes: Data) throws {
    guard !candidateBytes.isEmpty, sha256(candidateBytes) == envelope.installerHash else { try reject() }
    let syntheticContinuationRoot = try syntheticPhaseBContinuationRoot(envelope)
    if let syntheticContinuationRoot {
        try writeSyntheticContinuationMarker(
            syntheticContinuationRoot, "publisher1-supervisor.invocation", Data("SUPERVISOR_INVOCATION_1\n".utf8)
        )
    }
    let parentPath = (envelope.installerRoot as NSString).deletingLastPathComponent
    let finalName = (envelope.installerRoot as NSString).lastPathComponent
    let parentChain = try openDirectoryChain(parentPath, create: true)
    defer { for descriptor in parentChain.reversed() { Darwin.close(descriptor) } }
    let parent = parentChain.last!
    if try statAt(parent, finalName) != nil {
        let installedPath = try finishExactPromotedInstallerDirectoryFreeze(envelope)
        try continueThroughDurablePhaseB(
            installedPath, envelope: envelope, artifactRoot: syntheticContinuationRoot
        )
        return
    }
    let stagingName = ".immutable-installer-staging-\(envelope.generation)"
    if try statAt(parent, stagingName) == nil {
        guard stagingName.withCString({ Darwin.mkdirat(parent, $0, 0o700) }) == 0 else { try reject() }
    }
    let staging = try openDirectoryAt(parent, stagingName, create: false)
    defer { Darwin.close(staging) }
    let runtime = try openDirectoryAt(staging, "runtime", create: true)
    defer { Darwin.close(runtime) }
    if let existing = try readExistingAt(runtime, "ci3-publisher1-bootstrap-installer") {
        guard existing == candidateBytes else { try reject() }
        let metadata = try statAt(runtime, "ci3-publisher1-bootstrap-installer")
        guard let metadata, (metadata.st_mode & S_IFMT) == S_IFREG,
              (metadata.st_mode & 0o777) == 0o555, metadata.st_nlink == 1 else { try reject() }
    } else {
        try writeExclusiveAt(runtime, "ci3-publisher1-bootstrap-installer", candidateBytes, 0o555)
    }
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_IMMUTABLE_CRASH_AFTER"] == "BEFORE_SELF_FREEZE" { try reject() }
#endif
    try freezeLeafAt(runtime, "ci3-publisher1-bootstrap-installer", 0o555)
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_IMMUTABLE_CRASH_AFTER"] == "AFTER_SELF_FREEZE" { try reject() }
#endif
    let installedPath = (envelope.installerRoot as NSString).appendingPathComponent("runtime/ci3-publisher1-bootstrap-installer")
    let bootstrapReceipt = try immutableBootstrapReceipt(envelope, installedPath: installedPath)
    if let existing = try readExistingAt(staging, "immutable-installer-bootstrap.receipt.json") {
        guard existing == bootstrapReceipt else { try reject() }
        let metadata = try statAt(staging, "immutable-installer-bootstrap.receipt.json")
        guard let metadata, (metadata.st_mode & S_IFMT) == S_IFREG,
              (metadata.st_mode & 0o777) == 0o444, metadata.st_nlink == 1 else { try reject() }
    } else {
        try writeExclusiveAt(staging, "immutable-installer-bootstrap.receipt.json", bootstrapReceipt, 0o444)
    }
    try freezeLeafAt(staging, "immutable-installer-bootstrap.receipt.json", 0o444)
    try requireExactDirectoryChildren(runtime, ["ci3-publisher1-bootstrap-installer"])
    try requireExactDirectoryChildren(staging, ["runtime", "immutable-installer-bootstrap.receipt.json"])
    guard Darwin.fsync(runtime) == 0, Darwin.fsync(staging) == 0, Darwin.fsync(parent) == 0 else { try reject() }
    let promoted = stagingName.withCString { source in
        finalName.withCString { destination in
            Darwin.renameatx_np(parent, source, parent, destination, UInt32(RENAME_EXCL))
        }
    }
    guard promoted == 0, Darwin.fsync(parent) == 0 else { try reject() }
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_IMMUTABLE_CRASH_AFTER"] == "AFTER_PROMOTION_BEFORE_DIRECTORY_FREEZE" { try reject() }
#endif
    let finalRoot = try openDirectoryAt(parent, finalName, create: false)
    defer { Darwin.close(finalRoot) }
    let finalRuntime = try openDirectoryAt(finalRoot, "runtime", create: false)
    defer { Darwin.close(finalRuntime) }
    try freezeOwnedDescriptor(finalRuntime, 0o555)
    try freezeOwnedDescriptor(finalRoot, 0o555)
    let verifiedPath = try verifyImmutableInstallerTree(envelope)
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_IMMUTABLE_CRASH_AFTER"] == "PHASE_A" { try reject() }
#endif
    try continueThroughDurablePhaseB(
        verifiedPath, envelope: envelope, artifactRoot: syntheticContinuationRoot
    )
}

private func bootstrapSelfPhaseA(_ arguments: [String]) throws {
    let envelope = try parseImmutableBootstrapEnvelope(arguments, phase: "--immutable-bootstrap-phase-a")
    // argv[0] is caller-controlled. Authenticate the image the kernel actually
    // loaded; the privileged supervisor may deliberately supply a neutral argv0.
    let loadedImagePath = try currentExecutablePath()
    let candidateDescriptor = Darwin.open(loadedImagePath, O_RDONLY | O_NOFOLLOW)
    guard candidateDescriptor >= 0 else { try reject() }
    let candidateBeforeStat = try fstatValue(candidateDescriptor)
    guard (candidateBeforeStat.st_mode & S_IFMT) == S_IFREG else { Darwin.close(candidateDescriptor); try reject() }
    let candidateBefore = try physical(candidateBeforeStat)
    defer { Darwin.close(candidateDescriptor) }
    let candidateBytes = try readDescriptor(candidateDescriptor)
    guard candidateBefore.nlink == 1, sha256(candidateBytes) == envelope.installerHash,
          (try physical(try fstatValue(candidateDescriptor))).identity() == candidateBefore.identity() else { try reject() }
    try bootstrapSelectedPhaseA(envelope, candidateBytes: candidateBytes)
}

private func privilegedSupervisor(_ arguments: [String]) throws {
    guard arguments.count == 7, arguments[0] == "--privileged-supervisor",
          safeAbsolutePath(arguments[1]), isHex(arguments[2]), safeAbsolutePath(arguments[3]),
          isHex(arguments[4]), safeAbsolutePath(arguments[5]), isHex(arguments[6]) else { try reject() }
#if !CI3_SYNTHETIC_TEST
    guard getuid() == 0, geteuid() == 0 else { try reject() }
#endif
    let candidate = try openPinnedFile(arguments[1])
    defer { Darwin.close(candidate.descriptor); Darwin.close(candidate.parent) }
    guard candidate.before.mode == 0o700, candidate.before.nlink == 1 else { try reject() }
    let candidateBytes = try readDescriptor(candidate.descriptor, limit: 256 * 1024 * 1024)
    guard sha256(candidateBytes) == arguments[2],
          try physical(fstatValue(candidate.descriptor)).identity() == candidate.before.identity() else { try reject() }
    let envelope = try parseImmutableBootstrapEnvelope(
        ["--immutable-bootstrap-phase-a", arguments[3], arguments[4]], phase: "--immutable-bootstrap-phase-a"
    )
    try validatePrivilegedBoundary(arguments[5], expectedHash: arguments[6], envelope: envelope)
    var named = stat()
    guard candidate.leaf.withCString({ Darwin.fstatat(candidate.parent, $0, &named, AT_SYMLINK_NOFOLLOW) }) == 0,
          try physical(named).identity() == candidate.before.identity(),
          try physical(fstatValue(candidate.descriptor)).identity() == candidate.before.identity() else { try reject() }
    try bootstrapSelectedPhaseA(envelope, candidateBytes: candidateBytes)
}

private func publishImmutablePhaseB(_ arguments: [String]) throws {
    let envelope = try parseImmutableBootstrapEnvelope(arguments, phase: "--immutable-bootstrap-phase-b")
    let installedPath = try verifyImmutableInstallerTree(envelope)
    let executablePath = try currentExecutablePath()
    guard executablePath == URL(fileURLWithPath: installedPath).resolvingSymlinksInPath().path else { try reject() }
    try publish(envelope.request)
}

private func prepareLocal(_ arguments: [String]) throws {
    guard arguments == ["--prepare-local"] else { try reject() }
    let bytes = FileHandle.standardInput.readDataToEndOfFile()
    guard !bytes.isEmpty, bytes.count <= 16 * 1024 * 1024 else { try reject() }
    guard let request = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { try reject() }
    let hasTransactionRoot = request["transaction_receiver_root"] != nil
    try exactKeys(request, hasTransactionRoot
        ? ["schema_version", "purpose", "authority_sha", "controller_generation_id", "candidate_root", "transaction_receiver_root", "candidates", "prompt_sha256", "attempt", "retry", "raw_values"]
        : ["schema_version", "purpose", "authority_sha", "controller_generation_id", "candidate_root", "candidates", "prompt_sha256", "attempt", "retry", "raw_values"])
    let authority = try string(request["authority_sha"])
    let generation = try string(request["controller_generation_id"])
    let candidateRoot = try string(request["candidate_root"])
    let transactionReceiverRoot = hasTransactionRoot ? try string(request["transaction_receiver_root"]) : nil
    let candidates = try array(request["candidates"])
    guard try integer(request["schema_version"]) == 1,
          try string(request["purpose"]) == "CI3_PUBLISHER1_LOCAL_PREPARE_V1",
          isHex(authority, 40), isGeneration(generation), safeAbsolutePath(candidateRoot),
          candidateRoot.hasSuffix("/\(authority)/candidates"), isHex(try string(request["prompt_sha256"])),
          try integer(request["attempt"]) == 1, try boolean(request["retry"]) == false,
          try boolean(request["raw_values"]) == false, candidates.count == localPrepareRoles.count else { try reject() }
    if let transactionReceiverRoot {
        guard safeAbsolutePath(transactionReceiverRoot), transactionReceiverRoot.contains("/receiver/"),
              !transactionReceiverRoot.hasSuffix("/") else { try reject() }
    }
    let chain = try openDirectoryChain(candidateRoot, create: true)
    defer { for descriptor in chain.reversed() { Darwin.close(descriptor) } }
    let candidateFD = chain.last!
    let candidateIdentity = try physical(fstatValue(candidateFD))
    let transactionChain = try transactionReceiverRoot.map { try openDirectoryChain($0, create: true) }
    defer { if let transactionChain { for descriptor in transactionChain.reversed() { Darwin.close(descriptor) } } }
    let transactionIdentity = try transactionChain.map { try physical(fstatValue($0.last!)) }
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_PREPARE_SWAP_PARENT"] == "1" {
        let authorityRoot = (candidateRoot as NSString).deletingLastPathComponent
        let displaced = authorityRoot + ".displaced"
        guard Darwin.rename(authorityRoot, displaced) == 0, Darwin.mkdir(authorityRoot, 0o700) == 0,
              Darwin.mkdir((authorityRoot as NSString).appendingPathComponent("candidates"), 0o700) == 0 else { try reject() }
    }
#endif
    for (index, candidate) in candidates.enumerated() {
        try exactKeys(candidate, ["role", "bytes_base64"])
        let role = try string(candidate["role"])
        let encoded = try string(candidate["bytes_base64"])
        guard role == localPrepareRoles[index], let payload = Data(base64Encoded: encoded),
              !payload.isEmpty, payload.count <= 16 * 1024 * 1024,
              payload.base64EncodedString() == encoded else { try reject() }
        try writeExclusiveAt(candidateFD, "\(role).candidate", payload, 0o600, rootOwned: false)
    }
    let reopened = try openDirectoryChain(candidateRoot, create: false)
    defer { for descriptor in reopened.reversed() { Darwin.close(descriptor) } }
    guard samePinnedDirectory(try physical(fstatValue(candidateFD)), candidateIdentity),
          samePinnedDirectory(try physical(fstatValue(reopened.last!)), candidateIdentity),
          Darwin.fsync(candidateFD) == 0 else { try reject() }
    if let transactionReceiverRoot, let transactionChain, let transactionIdentity {
        let transactionReopened = try openDirectoryChain(transactionReceiverRoot, create: false)
        defer { for descriptor in transactionReopened.reversed() { Darwin.close(descriptor) } }
        guard samePinnedDirectory(try physical(fstatValue(transactionChain.last!)), transactionIdentity),
              samePinnedDirectory(try physical(fstatValue(transactionReopened.last!)), transactionIdentity),
              Darwin.fsync(transactionChain.last!) == 0 else { try reject() }
    }
    print("CI3_PUBLISHER1_LOCAL_PREPARE PASS raw_values=false")
}

private func claimBytes(_ request: Request) -> Data {
    Data("{\"schema_version\":1,\"purpose\":\"CI3_PUBLISHER1_BOOTSTRAP_CLAIM_V1\",\"authority_sha\":\"\(request.authority)\",\"controller_generation_id\":\"\(request.generation)\",\"request_sha256\":\"\(request.hash)\",\"attempt\":1,\"retry\":false,\"raw_values\":false}\n".utf8)
}

private func observation(_ role: String, _ physical: Physical, _ bytes: Data) -> [String: Any] {
    [
        "role": role, "sha256": sha256(bytes), "uid": physical.uid, "gid": physical.gid,
        "mode": physical.mode, "nlink": physical.nlink, "size": physical.size,
        "mtime_ns": physical.mtimeNS, "dev": physical.dev, "ino": physical.ino,
        "identity_sha256": physical.identity(),
    ]
}

private func resultBytes(_ request: Request, _ claim: Data, _ observations: [[String: Any]]) throws -> Data {
    try canonicalJSON([
        "schema_version": 1, "purpose": "CI3_PUBLISHER1_BOOTSTRAP_RESULT_V1",
        "authority_sha": request.authority, "controller_generation_id": request.generation,
        "claim_sha256": sha256(claim), "request_sha256": request.hash,
        "source_observations": request.entries.map { observation($0.role, $0.physical, $0.bytes) },
        "published_observations": observations, "terminal_state": "PUBLISHED", "raw_values": false,
    ])
}

private func verifyPublishedTree(_ destinationParent: Int32, _ finalName: String, _ request: Request) throws -> [[String: Any]] {
    let root = try openDirectoryAt(destinationParent, finalName, create: false)
    defer { Darwin.close(root) }
    try requireExactDirectoryChildren(root, ["publisher1-materializer.authority.json", "vps-issuer-authority.receipt.json", "runtime"])
    let rootPhysical = try physical(fstatValue(root))
    if productionMetadataRequired() {
        let rootStat = try fstatValue(root)
        guard rootPhysical.uid == Int(expectedPublishedUID()), rootPhysical.gid == Int(expectedPublishedGID()), rootPhysical.mode == 0o555,
              rootPhysical.nlink == 5,
              (rootStat.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try reject() }
    }
    var observations: [[String: Any]] = []
    for entry in request.entries {
        let parts = entry.relative.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { try reject() }
        var current = root
        var opened: [Int32] = []
        defer { for descriptor in opened.reversed() { Darwin.close(descriptor) } }
        for component in parts.dropLast() {
            let next = try openDirectoryAt(current, component, create: false)
            if component == "runtime" {
                try requireExactDirectoryChildren(next, [
                    "ci3-terminal-anchor-writer", "node", "ci3-bridge-controller.mjs", "ci3-bridge-launcher.zsh",
                    "launcher-bootstrap.authority.v1", "launch-attestation.json", "authority-manifest.v1",
                ])
            }
            let directoryPhysical = try physical(fstatValue(next))
            if productionMetadataRequired() {
                let directoryStat = try fstatValue(next)
                guard directoryPhysical.uid == Int(expectedPublishedUID()), directoryPhysical.gid == Int(expectedPublishedGID()), directoryPhysical.mode == 0o555,
                      directoryPhysical.nlink == 9,
                      (directoryStat.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { Darwin.close(next); try reject() }
            }
            opened.append(next)
            current = next
        }
        let leaf = parts.last!
        let descriptor = leaf.withCString { Darwin.openat(current, $0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { try reject() }
        defer { Darwin.close(descriptor) }
        let before = try physical(fstatValue(descriptor))
        let bytes = try readDescriptor(descriptor)
        let after = try physical(fstatValue(descriptor))
        var relative = stat()
        guard before.identity() == after.identity(), before.mode == Int(entry.mode), before.nlink == 1,
              bytes == entry.bytes,
              leaf.withCString({ Darwin.fstatat(current, $0, &relative, AT_SYMLINK_NOFOLLOW) }) == 0,
              (relative.st_mode & S_IFMT) == S_IFREG,
              (try physical(relative)).identity() == before.identity() else { try reject() }
        if productionMetadataRequired() {
            let leafStat = try fstatValue(descriptor)
            guard before.uid == Int(expectedPublishedUID()), before.gid == Int(expectedPublishedGID()),
                  (leafStat.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try reject() }
        }
        observations.append(observation(entry.role, before, bytes))
    }
    return observations
}

private func verifyStateTree(_ state: Int32, _ claim: Data, _ result: Data) throws {
    try requireExactDirectoryChildren(state, ["publisher1-bootstrap.claim.json", "publisher1-bootstrap.result.json"])
    guard try readExistingAt(state, "publisher1-bootstrap.claim.json") == claim,
          try readExistingAt(state, "publisher1-bootstrap.result.json") == result else { try reject() }
    if productionMetadataRequired() {
        for leaf in ["publisher1-bootstrap.claim.json", "publisher1-bootstrap.result.json"] {
            let descriptor = leaf.withCString { Darwin.openat(state, $0, O_RDONLY | O_NOFOLLOW) }
            guard descriptor >= 0 else { try reject() }
            defer { Darwin.close(descriptor) }
            let observed = try fstatValue(descriptor)
            let metadata = try physical(observed)
            guard metadata.uid == Int(expectedPublishedUID()), metadata.gid == Int(expectedPublishedGID()),
                  metadata.mode == 0o444, metadata.nlink == 1,
                  (observed.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try reject() }
        }
        let stateStat = try fstatValue(state)
        let statePhysical = try physical(stateStat)
        guard statePhysical.uid == Int(expectedPublishedUID()), statePhysical.gid == Int(expectedPublishedGID()),
              statePhysical.mode == 0o555, statePhysical.nlink == 4,
              (stateStat.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try reject() }
    }
}

private func freezePublishedTree(_ destinationParent: Int32, _ finalName: String, _ request: Request) throws {
    let root = try openDirectoryAt(destinationParent, finalName, create: false)
    defer { Darwin.close(root) }
    for entry in request.entries {
        let parts = entry.relative.split(separator: "/").map(String.init)
        var current = root
        var opened: [Int32] = []
        defer { for descriptor in opened.reversed() { Darwin.close(descriptor) } }
        for component in parts.dropLast() {
            let next = try openDirectoryAt(current, component, create: false)
            opened.append(next)
            current = next
        }
        let descriptor = parts.last!.withCString { Darwin.openat(current, $0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { try reject() }
        defer { Darwin.close(descriptor) }
        let before = try physical(fstatValue(descriptor))
        guard before.nlink == 1, before.mode == Int(entry.mode), try readDescriptor(descriptor) == entry.bytes else { try reject() }
        try freezeOwnedDescriptor(descriptor, entry.mode)
        guard Darwin.fsync(current) == 0 else { try reject() }
    }
    let runtime = try openDirectoryAt(root, "runtime", create: false)
    defer { Darwin.close(runtime) }
    try freezeOwnedDescriptor(runtime, 0o555)
    guard Darwin.fsync(root) == 0 else { try reject() }
    try freezeOwnedDescriptor(root, 0o555)
    guard Darwin.fsync(root) == 0, Darwin.fsync(destinationParent) == 0 else { try reject() }
}

private func publish(_ request: Request) throws {
    let parentPath = (request.destination as NSString).deletingLastPathComponent
    let finalName = (request.destination as NSString).lastPathComponent
    let stateParentPath = (request.state as NSString).deletingLastPathComponent
    let stateName = (request.state as NSString).lastPathComponent
    guard !finalName.isEmpty, finalName != ".", finalName != "..",
          !stateName.isEmpty, stateName != ".", stateName != ".." else { try reject() }
    let destinationChain = try openDirectoryChain(parentPath, create: true)
    let stateParentChain = try openDirectoryChain(stateParentPath, create: true)
    let stateParent = stateParentChain.last!
    let stateWasPresent = try statAt(stateParent, stateName) != nil
    if !stateWasPresent {
        guard stateName.withCString({ Darwin.mkdirat(stateParent, $0, 0o700) }) == 0,
              Darwin.fsync(stateParent) == 0 else { try reject() }
    }
    let state = try openDirectoryAt(stateParent, stateName, create: false)
    defer {
        Darwin.close(state)
        for descriptor in stateParentChain.reversed() { Darwin.close(descriptor) }
        for descriptor in destinationChain.reversed() { Darwin.close(descriptor) }
    }
    let destinationParent = destinationChain.last!
    let destinationIdentity = try physical(fstatValue(destinationParent))
    let stateIdentity = try physical(fstatValue(state))
    let claim = claimBytes(request)
    let existingClaim = try readExistingAt(state, "publisher1-bootstrap.claim.json")
    let existingDestination = try statAt(destinationParent, finalName)
    if stateWasPresent && existingClaim == nil { try reject() }
    if existingClaim != nil || existingDestination != nil {
        guard existingClaim == claim, let destination = existingDestination,
              (destination.st_mode & S_IFMT) == S_IFDIR else { try reject() }
        let observations = try verifyPublishedTree(destinationParent, finalName, request)
        let result = try resultBytes(request, claim, observations)
        try verifyStateTree(state, claim, result)
        print("CI3_PUBLISHER1_BOOTSTRAP_INSTALL PASS status=EXISTS_VERIFIED effect_executions=0")
        return
    }
    try writeExclusiveAt(state, "publisher1-bootstrap.claim.json", claim, 0o444)
    try freezeLeafAt(state, "publisher1-bootstrap.claim.json", 0o444)
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_CRASH_AFTER"] == "CLAIM" { try reject() }
#endif
    let stagingName = ".staging-\(request.generation)"
    guard stagingName.withCString({ Darwin.mkdirat(destinationParent, $0, 0o700) }) == 0 else { try reject() }
    let staging = try openDirectoryAt(destinationParent, stagingName, create: false)
    defer { Darwin.close(staging) }
    for entry in request.entries {
        let parts = entry.relative.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { try reject() }
        var current = staging
        var opened: [Int32] = []
        defer { for descriptor in opened.reversed() { Darwin.close(descriptor) } }
        for component in parts.dropLast() {
            let next = try openDirectoryAt(current, component, create: true)
            opened.append(next)
            current = next
        }
        try writeExclusiveAt(current, parts.last!, entry.bytes, entry.mode)
    }
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_SWAP_DESTINATION_PARENT"] == "1" {
        let displaced = parentPath + ".displaced"
        guard Darwin.rename(parentPath, displaced) == 0, Darwin.mkdir(parentPath, 0o700) == 0 else { try reject() }
    }
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_SWAP_STATE_PARENT"] == "1" {
        let displaced = request.state + ".displaced"
        guard Darwin.rename(request.state, displaced) == 0, Darwin.mkdir(request.state, 0o700) == 0 else { try reject() }
    }
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_CREATE_FINAL_NAME"] == "1" {
        guard finalName.withCString({ Darwin.mkdirat(destinationParent, $0, 0o700) }) == 0 else { try reject() }
    }
#endif
    guard Darwin.fsync(staging) == 0, Darwin.fsync(destinationParent) == 0,
          samePinnedDirectory(try physical(fstatValue(destinationParent)), destinationIdentity),
          samePinnedDirectory(try physical(fstatValue(state)), stateIdentity),
          try namedDirectoryStillMatches(parentPath, destinationIdentity),
          try namedDirectoryStillMatches(request.state, stateIdentity) else { try reject() }
    let promoted = stagingName.withCString { source in
        finalName.withCString { destination in
            Darwin.renameatx_np(destinationParent, source, destinationParent, destination, UInt32(RENAME_EXCL))
        }
    }
    guard promoted == 0, Darwin.fsync(destinationParent) == 0 else { try reject() }
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_CRASH_AFTER"] == "PROMOTION" { try reject() }
#endif
    try freezePublishedTree(destinationParent, finalName, request)
    let observations = try verifyPublishedTree(destinationParent, finalName, request)
    guard samePinnedDirectory(try physical(fstatValue(destinationParent)), destinationIdentity),
          samePinnedDirectory(try physical(fstatValue(state)), stateIdentity),
          try namedDirectoryStillMatches(parentPath, destinationIdentity),
          try namedDirectoryStillMatches(request.state, stateIdentity) else { try reject() }
    try writeExclusiveAt(state, "publisher1-bootstrap.result.json", try resultBytes(request, claim, observations), 0o444)
    try freezeLeafAt(state, "publisher1-bootstrap.result.json", 0o444)
    let result = try resultBytes(request, claim, observations)
    try freezeOwnedDescriptor(state, 0o555)
    guard Darwin.fsync(stateParent) == 0 else { try reject() }
    try verifyStateTree(state, claim, result)
    print("CI3_PUBLISHER1_BOOTSTRAP_INSTALL PASS status=CREATED effect_executions=1")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "--prepare-local" {
        try prepareLocal(arguments)
    } else if arguments.first == "--privileged-supervisor" {
        try privilegedSupervisor(arguments)
    } else if arguments.first == "--immutable-bootstrap-phase-a" {
        try bootstrapSelfPhaseA(arguments)
    } else if arguments.first == "--immutable-bootstrap-phase-b" {
        try publishImmutablePhaseB(arguments)
        } else if arguments.first == "--durable-immutable-bootstrap-phase-b" {
            try runDurablePhaseBWorker(arguments)
            } else if arguments.first == "--durable-immutable-bootstrap-activation-owner" {
                try runDurablePhaseBActivationOwner(arguments)
            } else if arguments.first == "--synthetic-durable-phase-b-kickstart" {
#if CI3_SYNTHETIC_TEST
                try runSyntheticDurablePhaseBKickstart(arguments)
#else
                try reject()
#endif
            } else if arguments.first == "--durable-immutable-bootstrap-registrar" {
                try runDurablePhaseBRegistrar(arguments)
            } else if arguments.first == "--durable-immutable-bootstrap-registrar-supervisor" {
                try runDurablePhaseBRegistrarSupervisor(arguments)
            } else if arguments.first == "--synthetic-durable-control-probe" {
#if CI3_SYNTHETIC_TEST
            try runSyntheticDurableControlProbe(arguments)
#else
            try reject()
#endif
        } else {
#if CI3_SYNTHETIC_TEST
        try publish(try parseRequest(arguments))
#else
        try reject()
#endif
    }
} catch {
    fputs("ERROR PUBLISHER1_BOOTSTRAP\n", stderr)
    exit(1)
}
