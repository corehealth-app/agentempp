import Foundation
import Darwin
import CryptoKit

private let scanIDs = ["argv", "history", "terminal-log", "attachment", "xcresult", "runtime"]
private let scannerSchemaHashes = [
    "argv": "45069ac37d719f58b9953aa652edad500e5783de69f1fd78c6338da3e3af9d40",
    "history": "b1c4486ac592208f7500b353c5c83474e6a3150f4c4f85a609f233042402891f",
    "terminal-log": "9b881b1b9e5443514a2f7825a9ec7f9a29eb5964d9ad974b2a845bee8e6b08ac",
    "attachment": "6c64c69fe646bc5b08f8e65d249077b0f4eb781b58ddf1bb3d7f64e6337a78cb",
    "xcresult": "bb8f030b96679ac38caffadd971e259a265170c0748d7ddf94e8b317833da944",
    "runtime": "53aa749f147360e7e77312ac012c7f595b773ed2248cb12d7165fa729706477a",
]
private let ci3SourceCommit = "277873755bf29771a10b5f362b522c2e6a6c21d6"
private let findingIDs = [
    "RA1-I-5", "A4-I-1", "A4-I-3", "A5-I-1", "A5-I-2",
    "RA0-I-4", "RA0-I-7", "R2-I-2", "R5-I-1", "R5-I-2", "R5-I-3",
] + (1...6).map { "RA-FINAL-I-\($0)" } + (1...7).map { "RB-FINAL-I-\($0)" }
private let componentNames = ["generator", "controller", "launcher", "writer"]
private let componentPaths = [
    "generator": "scripts/ci3/create-ios-staging-bridge-config.mjs",
    "controller": "scripts/ci3/ci3-bridge-controller.mjs",
    "launcher": "scripts/ci3/ci3-bridge-launcher.zsh",
    "writer": "scripts/ci3/ci3-terminal-anchor-writer.swift",
]
private let authorityPaths = [
    "docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md",
    "docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md",
    "docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md",
    "docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md",
    "docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md",
    "scripts/ci3/create-ios-staging-bridge-config.mjs",
    "scripts/ci3/create-ios-staging-bridge-config.test.mjs",
    "scripts/ci3/ci3-bridge-controller.mjs",
    "scripts/ci3/ci3-bridge-controller.test.mjs",
    "scripts/ci3/ci3-bridge-launcher.zsh",
    "scripts/ci3/ci3-bridge-launcher.test.mjs",
    "scripts/ci3/ci3-terminal-anchor-writer.swift",
    "scripts/ci3/ci3-terminal-anchor-writer.test.mjs",
]
private let simulatorPhases = ["SELECT_DEVICE", "RESOLVE_CONTAINER", "INSTALL_PROBE", "LAUNCH_PROBE", "ACK_PROBE", "REMOVE_PROBE", "REOBSERVE"]
private let controllerEvidencePhases = ["VERIFY_AUTHORITY", "VERIFY_WORKTREE", "VERIFY_SIMULATOR", "VERIFY_SSH", "PUBLISH_LOCAL", "INSTALL_SIMULATOR", "REMOVE_CREDENTIAL", "RUN_SCANS"]
private let terminalSettlementPhases = ["INVOKE_WRITER", "VERIFY_ANCHOR"]
private let terminalFinalSurfaceRoles = [
    "process-argv", "controller-journal", "controller-stdout", "controller-stderr",
    "terminal-attachments", "simulator-xcresult", "runtime-environment",
    "writer-output", "terminal-settlement", "complete-result",
]
private func evidencePrefix(_ namespace: String, _ phase: String) -> String {
    "\(namespace)-phase-\(phase.lowercased().replacingOccurrences(of: "_", with: "-"))"
}
private let evidenceRoles = [
    "authority-manifest", "launch-attestation", "bootstrap-claim", "receipt-read-claim", "receipt-read-result",
    "config-read-claim", "config-read-result", "credential-read-claim", "credential-read-result",
    "remote-receipt", "local-receipt", "ssh-provenance", "simulator-gate",
    "simulator-install", "input-manifest", "terminal-receipt", "controller-durable-state-root", "writer-source",
    "operation-authority-root", "vps-pass-root", "vps-issuer-authority-root",
    "human-authorization-root", "publisher-input-manifest-root",
    "ssh-trust-descriptor", "ssh-public-key", "ssh-public-key-fingerprint",
] + simulatorPhases.flatMap { phase in ["claim", "receipt", "result"].map { "\(evidencePrefix("simulator", phase))-\($0)" } }
  + controllerEvidencePhases.flatMap { phase in ["claim", "receipt", "result"].map { "\(evidencePrefix("controller", phase))-\($0)" } }

private struct WriterFailure: Error {
    let code: String
}

private var semanticSection = "ROOT"

@inline(__always) private func fail(_ code: String) throws -> Never {
    throw WriterFailure(code: code == "TERMINAL_SEMANTICS" ? "TERMINAL_SEMANTICS_\(semanticSection)" : code)
}

private func isHex(_ value: String, count: Int) -> Bool {
    value.count == count && value.unicodeScalars.allSatisfy {
        (48...57).contains($0.value) || (97...102).contains($0.value)
    }
}

private func isGeneration(_ value: String, prefix: String) -> Bool {
    value.hasPrefix("\(prefix)-") && isHex(String(value.dropFirst(prefix.count + 1)), count: 64)
}

private func canonicalRemoteCommand(_ remotePath: String, _ code: String) throws -> String {
    guard remotePath.hasPrefix("/"), !remotePath.hasSuffix("/"), !remotePath.contains("//"),
          !remotePath.contains("/../"),
          remotePath.range(of: "^/[A-Za-z0-9._/-]+$", options: .regularExpression) != nil else { try fail(code) }
    return "exec /usr/bin/cat -- \(remotePath)"
}

private func dictionary(_ value: Any?, _ code: String) throws -> [String: Any] {
    guard let result = value as? [String: Any] else { try fail(code) }
    return result
}

private func array(_ value: Any?, _ code: String) throws -> [Any] {
    guard let result = value as? [Any] else { try fail(code) }
    return result
}

private func string(_ value: Any?, _ code: String) throws -> String {
    guard let result = value as? String, !result.isEmpty else { try fail(code) }
    return result
}

private func bool(_ value: Any?, _ code: String) throws -> Bool {
    guard let result = value as? Bool else { try fail(code) }
    return result
}

private func integer(_ value: Any?, _ code: String) throws -> Int {
    guard let result = value as? NSNumber else { try fail(code) }
    return result.intValue
}

private func exactKeys(_ dictionary: [String: Any], _ keys: [String], _ code: String) throws {
    guard Set(dictionary.keys) == Set(keys), dictionary.keys.count == keys.count else { try fail(code) }
}

private func isUTCTimestamp(_ value: String) -> Bool {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) != nil && value.hasSuffix("Z")
}

private func jsonObject(_ data: Data, _ code: String) throws -> [String: Any] {
    do {
        return try dictionary(JSONSerialization.jsonObject(with: data), code)
    } catch let error as WriterFailure {
        throw error
    } catch {
        try fail(code)
    }
}

private func jsonBytes(_ value: [String: Any]) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    data.append(0x0a)
    return data
}

private func compactJSONBytes(_ value: [String: Any]) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    data.append(0x0a)
    return data
}

private func compactJSONArrayBytes(_ value: [[String: Any]]) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    data.append(0x0a)
    return data
}

private func sha256(_ data: Data) throws -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private struct Physical: Equatable {
    let uid: UInt32
    let gid: UInt32
    let mode: UInt16
    let nlink: UInt16
    let size: Int64
    let mtimeNS: String
    let dev: String
    let ino: String
    let flags: UInt32
}

private func physical(_ value: stat) -> Physical {
    let nanoseconds = Int64(value.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(value.st_mtimespec.tv_nsec)
    return Physical(
        uid: value.st_uid,
        gid: value.st_gid,
        mode: UInt16(value.st_mode & 0o777),
        nlink: UInt16(value.st_nlink),
        size: value.st_size,
        mtimeNS: String(nanoseconds),
        dev: String(value.st_dev),
        ino: String(value.st_ino),
        flags: value.st_flags
    )
}

private func physicalIdentityHash(_ value: Physical) throws -> String {
    let bytes = Data("uid=\(value.uid);gid=\(value.gid);mode=\(value.mode);nlink=\(value.nlink);size=\(value.size);mtime=\(value.mtimeNS);dev=\(value.dev);ino=\(value.ino)".utf8)
    return try sha256(bytes)
}

private func sameDirectoryIdentity(_ left: Physical, _ right: Physical) -> Bool {
    left.dev == right.dev && left.ino == right.ino && left.uid == right.uid
        && left.gid == right.gid && left.mode == right.mode
}

private func physicalObservationHash(_ entry: [String: Any], _ bytes: Data, _ code: String) throws -> String {
    let metadata = try dictionary(entry["metadata"], code)
    try exactKeys(metadata, ["dev", "gid", "ino", "mode", "mtime_ns", "nlink", "size", "uid"], code)
    let uid = try integer(metadata["uid"], code)
    let gid = try integer(metadata["gid"], code)
    let mode = try integer(metadata["mode"], code)
    let nlink = try integer(metadata["nlink"], code)
    let size = try integer(metadata["size"], code)
    let mtime = try string(metadata["mtime_ns"], code)
    let dev = try string(metadata["dev"], code)
    let ino = try string(metadata["ino"], code)
    guard nlink == 1, size == bytes.count, !mtime.isEmpty, !dev.isEmpty, !ino.isEmpty else { try fail(code) }
    return try sha256(Data("bytes=\(sha256(bytes));uid=\(uid);gid=\(gid);mode=\(mode & 0o777);nlink=\(nlink);size=\(size);mtime=\(mtime);dev=\(dev);ino=\(ino)".utf8))
}

private func lstatValue(_ path: String, _ code: String) throws -> stat {
    var value = stat()
    guard path.withCString({ Darwin.lstat($0, &value) }) == 0 else { try fail(code) }
    return value
}

private func fstatValue(_ descriptor: Int32, _ code: String) throws -> stat {
    var value = stat()
    guard Darwin.fstat(descriptor, &value) == 0 else { try fail(code) }
    return value
}

private func readBoundFile(_ path: String, expected: [String: Any]? = nil, mode: UInt16 = 0o600, code: String) throws -> (Data, Physical) {
    let beforePath = try lstatValue(path, code)
    guard (beforePath.st_mode & S_IFMT) == S_IFREG, beforePath.st_nlink == 1, UInt16(beforePath.st_mode & 0o777) == mode else { try fail(code) }
    let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { try fail(code) }
    defer { Darwin.close(descriptor) }
    let beforeFD = try fstatValue(descriptor, code)
    guard physical(beforeFD) == physical(beforePath) else { try fail(code) }
    var bytes = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        if count < 0 { try fail(code) }
        if count == 0 { break }
        bytes.append(buffer, count: count)
        if bytes.count > 4 * 1024 * 1024 { try fail(code) }
    }
    let afterFD = try fstatValue(descriptor, code)
    let afterPath = try lstatValue(path, code)
    let observed = physical(afterFD)
    guard observed == physical(beforeFD), observed == physical(afterPath) else { try fail(code) }
    if let expected {
        try exactKeys(expected, ["dev", "gid", "ino", "mode", "mtime_ns", "nlink", "size", "uid"], code)
        guard try integer(expected["uid"], code) == Int(observed.uid),
              try integer(expected["gid"], code) == Int(observed.gid),
              try integer(expected["mode"], code) == Int(observed.mode),
              try integer(expected["nlink"], code) == Int(observed.nlink),
              try integer(expected["size"], code) == Int(observed.size),
              try string(expected["mtime_ns"], code) == observed.mtimeNS,
              try string(expected["dev"], code) == observed.dev,
              try string(expected["ino"], code) == observed.ino else { try fail(code) }
    }
    return (bytes, observed)
}

private func validateComponent(_ value: [String: Any], name: String, _ code: String) throws {
    try exactKeys(value, ["blob_oid", "path", "sha256"], code)
    guard try string(value["path"], code) == componentPaths[name] else { try fail(code) }
    guard isHex(try string(value["blob_oid"], code), count: 40),
          isHex(try string(value["sha256"], code), count: 64) else { try fail(code) }
}

private func validateGenerationArguments(_ generations: [String: Any], _ arguments: [String], _ code: String) throws {
    try exactKeys(generations, ["controller", "remote", "simulator", "terminal"], code)
    let remote = try string(generations["remote"], code)
    let controller = try string(generations["controller"], code)
    let simulator = try string(generations["simulator"], code)
    let terminal = try string(generations["terminal"], code)
    guard isGeneration(remote, prefix: "remote"), isGeneration(controller, prefix: "controller"),
          isGeneration(simulator, prefix: "simulator"), isGeneration(terminal, prefix: "terminal") else { try fail(code) }
    guard arguments == [remote, controller, simulator, terminal] else { try fail("GENERATION_MISMATCH") }
}

private func validateEvidence(_ values: [Any], _ code: String) throws -> [[String: Any]] {
    guard values.count == evidenceRoles.count else { try fail(code) }
    var result: [[String: Any]] = []
    for (index, role) in evidenceRoles.enumerated() {
        let entry = try dictionary(values[index], code)
        try exactKeys(entry, ["metadata", "path", "role", "sha256"], code)
        guard try string(entry["role"], code) == role else { try fail(code) }
        let path = try string(entry["path"], code)
        guard path.hasPrefix("/") && !path.contains("/../") else { try fail(code) }
        let expectedHash = try string(entry["sha256"], code)
        guard isHex(expectedHash, count: 64) else { try fail(code) }
        let metadata = try dictionary(entry["metadata"], code)
        let evidenceMode = UInt16(try integer(metadata["mode"], code))
        let (_, _) = try readBoundFile(path, expected: metadata, mode: evidenceMode, code: code)
        if [
            "operation-authority-root", "vps-pass-root", "vps-issuer-authority-root",
            "human-authorization-root", "publisher-input-manifest-root", "ssh-trust-descriptor", "ssh-public-key",
        ].contains(role) {
#if CI3_SYNTHETIC_TEST
            guard evidenceMode == 0o600 else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }
#else
            guard evidenceMode == 0o444, try integer(metadata["uid"], code) == 0,
                  try integer(metadata["gid"], code) == 0 else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }
#endif
        }
        let (bytes, _) = try readBoundFile(path, expected: metadata, mode: evidenceMode, code: code)
        guard try sha256(bytes) == expectedHash else { try fail(code) }
        result.append(entry)
    }
    return result
}

private func validateScanReceipts(_ values: [Any], authority: String, generations: [String: Any], _ code: String) throws -> [[String: Any]] {
    guard values.count == scanIDs.count else { try fail(code) }
    var result: [[String: Any]] = []
    for (index, scanID) in scanIDs.enumerated() {
        let entry = try dictionary(values[index], code)
        try exactKeys(entry, ["id", "metadata", "path", "sha256"], code)
        guard try string(entry["id"], code) == scanID else { try fail(code) }
        let expectedHash = try string(entry["sha256"], code)
        guard isHex(expectedHash, count: 64) else { try fail(code) }
        let (bytes, _) = try readBoundFile(try string(entry["path"], code), expected: try dictionary(entry["metadata"], code), code: code)
        guard try sha256(bytes) == expectedHash else { try fail(code) }
        let receipt = try jsonObject(bytes, code)
        try exactKeys(receipt, [
            "authority_sha", "command_sha256", "controller_generation_id", "finished_at",
            "counters", "input_manifest_sha256", "input_observations", "input_stable_after_scan", "local_bundle_sha256",
            "match_count", "output_sha256", "purpose", "redaction", "remote_generation_id",
            "result", "scan_id", "scanner_schema_sha256", "schema_version", "simulator_generation_id",
            "simulator_install_sha256", "started_at", "terminal_generation_id",
            "tool_sha256", "worktree_diff_sha256",
        ], code)
        guard try integer(receipt["schema_version"], code) == 1,
              try string(receipt["purpose"], code) == "CI3_TERMINAL_SCAN_RECEIPT_V1",
              try string(receipt["scan_id"], code) == scanID,
              try string(receipt["authority_sha"], code) == authority,
              try string(receipt["controller_generation_id"], code) == string(generations["controller"], code),
              try string(receipt["remote_generation_id"], code) == string(generations["remote"], code),
              try string(receipt["simulator_generation_id"], code) == string(generations["simulator"], code),
              try string(receipt["terminal_generation_id"], code) == string(generations["terminal"], code),
              isHex(try string(receipt["local_bundle_sha256"], code), count: 64),
              isHex(try string(receipt["simulator_install_sha256"], code), count: 64),
              isHex(try string(receipt["worktree_diff_sha256"], code), count: 64),
              isHex(try string(receipt["input_manifest_sha256"], code), count: 64),
              isHex(try string(receipt["tool_sha256"], code), count: 64),
              isHex(try string(receipt["command_sha256"], code), count: 64),
              isHex(try string(receipt["scanner_schema_sha256"], code), count: 64),
              isHex(try string(receipt["output_sha256"], code), count: 64),
              isUTCTimestamp(try string(receipt["started_at"], code)),
              isUTCTimestamp(try string(receipt["finished_at"], code)),
              try string(receipt["result"], code) == "CLEAN",
              try integer(receipt["match_count"], code) == 0,
              try bool(receipt["redaction"], code), try bool(receipt["input_stable_after_scan"], code) else { try fail(code) }
        let counters = try dictionary(receipt["counters"], code)
        try exactKeys(counters, ["jwt", "pii", "raw_destination", "secret", "token"], code)
        guard counters.values.allSatisfy({ (($0 as? NSNumber)?.intValue ?? -1) == 0 }) else { try fail(code) }
        let observations = try array(receipt["input_observations"], code)
        guard !observations.isEmpty else { try fail(code) }
        for rawObservation in observations {
            let observation = try dictionary(rawObservation, code)
            try exactKeys(observation, ["metadata", "path", "path_sha256", "sha256"], code)
            let inputPath = try string(observation["path"], code)
            guard inputPath.hasPrefix("/"), !inputPath.contains("/../"),
                  try string(observation["path_sha256"], code) == sha256(Data(inputPath.utf8)) else { try fail(code) }
            let (inputBytes, _) = try readBoundFile(inputPath, expected: try dictionary(observation["metadata"], code), code: code)
            guard try string(observation["sha256"], code) == sha256(inputBytes) else { try fail(code) }
        }
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let started = timestampFormatter.date(from: try string(receipt["started_at"], code)),
              let finished = timestampFormatter.date(from: try string(receipt["finished_at"], code)),
              finished >= started else { try fail(code) }
        result.append(entry)
    }
    return result
}

private func evidenceObject(_ entries: [[String: Any]], role: String, _ code: String) throws -> ([String: Any], Data, [String: Any]) {
    guard let entry = entries.first(where: { ($0["role"] as? String) == role }) else { try fail(code) }
    let metadata = try dictionary(entry["metadata"], code)
    let mode = UInt16(try integer(metadata["mode"], code))
    let (bytes, _) = try readBoundFile(try string(entry["path"], code), expected: metadata, mode: mode, code: code)
    guard try sha256(bytes) == string(entry["sha256"], code) else { try fail(code) }
    return (entry, bytes, try jsonObject(bytes, code))
}

private func containsSensitiveScanContent(_ bytes: Data, scanID: String) throws -> Bool {
    guard let text = String(data: bytes, encoding: .utf8) else { return true }
    let common = [
        #"(?i)(password|secret|service[_-]?role)[\s:=]+\S+"#,
        #"(?i)(bearer\s+|token|authorization)[\s:=]+\S+"#,
        #"\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
        #"\b[^\s@]+@[^\s@]+\.[^\s@]+\b"#,
        #"(?i)(host|destination|origin)[\s:=]+\S+"#,
        #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
    ]
    let specific: [String: [String]] = [
        "argv": [#"(?i)--(?:email|phone)=\S+"#],
        "history": [#"(?i)(?:export\s+)?(?:PASSWORD|SERVICE_ROLE|TOKEN)=\S+"#],
        "terminal-log": [#"(?i)(?:password|secret|token)[\s:=]+\S+"#],
        "attachment": [#"(?i)\"(?:password|secret|token|authorization|email|phone|host|destination|origin)\"\s*:\s*\"[^\"]+\""#],
        "xcresult": [#"(?i)(?:password|secret|serviceRole|token|authorization|email|phone|host|destination|origin)\s*=\s*\S+"#],
        "runtime": [#"(?:PASSWORD|SECRET|SERVICE_ROLE|TOKEN|AUTHORIZATION|EMAIL|PHONE|HOST|DESTINATION|ORIGIN)=\S+"#],
    ]
    guard let scanPatterns = specific[scanID] else { return true }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    for pattern in common + scanPatterns {
        let expression = try NSRegularExpression(pattern: pattern)
        if expression.firstMatch(in: text, range: range) != nil { return true }
    }
    return false
}

private func containsSensitiveSemanticSurface(_ bytes: Data, scanID: String) throws -> Bool {
    guard ["history", "terminal-log", "attachment"].contains(scanID) else {
        return try containsSensitiveScanContent(bytes, scanID: scanID)
    }
    guard let decoded = try? JSONSerialization.jsonObject(with: bytes), let records = decoded as? [[String: Any]] else {
        return try containsSensitiveScanContent(bytes, scanID: scanID)
    }
    for record in records {
        guard let encoded = record["content_base64"] as? String,
              let payload = Data(base64Encoded: encoded), payload.base64EncodedString() == encoded,
              let length = record["content_byte_length"] as? Int, length == payload.count,
              let expected = record["content_sha256"] as? String, expected == (try sha256(payload)) else { return true }
        if try containsSensitiveScanContent(payload, scanID: scanID) { return true }
    }
    return false
}

private func evidenceEntry(_ entries: [[String: Any]], role: String, _ code: String) throws -> [String: Any] {
    guard let entry = entries.first(where: { ($0["role"] as? String) == role }) else { try fail(code) }
    return entry
}

private func parseJournalFrame(_ frame: Data, _ code: String) throws -> [(String, Data)] {
    let bytes = [UInt8](frame)
    var offset = 0
    func length() throws -> Int {
        let start = offset
        while offset < bytes.count, bytes[offset] >= 48, bytes[offset] <= 57 { offset += 1 }
        guard offset > start, offset < bytes.count, bytes[offset] == 58,
              let value = Int(String(bytes: bytes[start..<offset], encoding: .utf8) ?? "") else { try fail(code) }
        offset += 1
        return value
    }
    var result: [(String, Data)] = []
    while offset < bytes.count {
        let pathLength = try length()
        guard pathLength >= 1, offset + pathLength < bytes.count,
              let relativePath = String(bytes: bytes[offset..<(offset + pathLength)], encoding: .utf8),
              !relativePath.hasPrefix("/"), !relativePath.contains("..") else { try fail(code) }
        offset += pathLength
        guard bytes[offset] == 10 else { try fail(code) }
        offset += 1
        let byteLength = try length()
        guard byteLength >= 0, offset + byteLength < bytes.count else { try fail(code) }
        let content = Data(bytes[offset..<(offset + byteLength)])
        offset += byteLength
        guard bytes[offset] == 10 else { try fail(code) }
        offset += 1
        result.append((relativePath, content))
    }
    return result
}

private func validatedJournalFrame(_ evidence: [[String: Any]], _ code: String) throws -> Data {
    let (_, bytes, root) = try evidenceObject(evidence, role: "controller-durable-state-root", code)
    let purpose = try string(root["purpose"], "TERMINAL_DURABLE_STATE")
    if purpose == "CI3_SYNTHETIC_DURABLE_PROTOCOL_STATE_V1" {
        try exactKeys(root, [
            "purpose", "raw_values", "scenario_id", "scenario_sha256", "schema_version",
            "snapshot", "snapshot_path_sha256", "snapshot_sha256",
        ], "TERMINAL_DURABLE_STATE")
        let snapshot = try dictionary(root["snapshot"], "TERMINAL_DURABLE_STATE")
        try exactKeys(snapshot, [
            "claims", "crash_observed", "events", "phase_claims", "phase_effect_counts", "phase_paths",
            "phase_produced", "phase_receipts", "phase_results", "records", "results", "scenario_trace",
        ], "TERMINAL_DURABLE_STATE")
        let scenario = try string(root["scenario_id"], "TERMINAL_DURABLE_STATE")
        guard try integer(root["schema_version"], "TERMINAL_DURABLE_STATE") == 1,
              try string(root["scenario_sha256"], "TERMINAL_DURABLE_STATE") == sha256(Data(scenario.utf8)),
              isHex(try string(root["snapshot_path_sha256"], "TERMINAL_DURABLE_STATE"), count: 64),
              try string(root["snapshot_sha256"], "TERMINAL_DURABLE_STATE") == sha256(compactJSONBytes(snapshot)),
              try bool(root["raw_values"], "TERMINAL_DURABLE_STATE") == false,
              (snapshot["crash_observed"] as? Bool) != nil else { try fail("TERMINAL_DURABLE_STATE") }
        for key in [
            "claims", "events", "phase_claims", "phase_effect_counts", "phase_paths", "phase_produced",
            "phase_receipts", "phase_results", "records", "results", "scenario_trace",
        ] { _ = try array(snapshot[key], "TERMINAL_DURABLE_STATE") }
        let terminalCommit: [String: Any] = [
            "terminal_commit_contract_sha256": try sha256(bytes),
        ]
        let completeEvent: [String: Any] = [
            "event": "COMPLETE", "state": "COMPLETE", "result": terminalCommit,
            "result_sha256": try sha256(compactJSONBytes(terminalCommit)),
        ]
        let completeBytes = try compactJSONBytes(completeEvent)
        let durablePath = "synthetic/controller-durable-state-root.json"
        let completePath = "events/COMPLETE.json"
        return Data("\(durablePath.utf8.count):\(durablePath)\n\(bytes.count):".utf8)
            + bytes + Data("\n\(completePath.utf8.count):\(completePath)\n\(completeBytes.count):".utf8)
            + completeBytes + Data("\n".utf8)
    }
    guard purpose == "CI3_OPERATIONAL_DURABLE_JOURNAL_FRAME_V1" else { try fail("TERMINAL_DURABLE_STATE") }
    try exactKeys(root, [
        "authority_sha", "frame_base64", "frame_byte_length", "frame_sha256", "generations",
        "object_count", "objects", "purpose", "raw_scanned_before_encoding", "raw_values", "schema_version",
    ], "TERMINAL_DURABLE_STATE")
    guard let frame = Data(base64Encoded: try string(root["frame_base64"], "TERMINAL_DURABLE_STATE"), options: []),
          try integer(root["schema_version"], "TERMINAL_DURABLE_STATE") == 1,
          try string(root["authority_sha"], "TERMINAL_DURABLE_STATE").count == 40,
          try integer(root["frame_byte_length"], "TERMINAL_DURABLE_STATE") == frame.count,
          try string(root["frame_sha256"], "TERMINAL_DURABLE_STATE") == sha256(frame),
          try bool(root["raw_scanned_before_encoding"], "TERMINAL_DURABLE_STATE") == true,
          try bool(root["raw_values"], "TERMINAL_DURABLE_STATE") == false else { try fail("TERMINAL_DURABLE_STATE") }
    let framed = try parseJournalFrame(frame, "TERMINAL_DURABLE_STATE")
    let objects = try array(root["objects"], "TERMINAL_DURABLE_STATE")
    guard try integer(root["object_count"], "TERMINAL_DURABLE_STATE") == framed.count,
          objects.count == framed.count else { try fail("TERMINAL_DURABLE_STATE") }
    for index in framed.indices {
        let object = try dictionary(objects[index], "TERMINAL_DURABLE_STATE")
        try exactKeys(object, ["byte_length", "identity_sha256", "path_sha256", "relative_path", "sha256"], "TERMINAL_DURABLE_STATE")
        let (relativePath, content) = framed[index]
        guard try string(object["relative_path"], "TERMINAL_DURABLE_STATE") == relativePath,
              try string(object["path_sha256"], "TERMINAL_DURABLE_STATE") == sha256(Data(relativePath.utf8)),
              try integer(object["byte_length"], "TERMINAL_DURABLE_STATE") == content.count,
              try string(object["sha256"], "TERMINAL_DURABLE_STATE") == sha256(content),
              isHex(try string(object["identity_sha256"], "TERMINAL_DURABLE_STATE"), count: 64) else { try fail("TERMINAL_DURABLE_STATE") }
        for scanID in scanIDs {
            guard try !containsSensitiveSemanticSurface(content, scanID: scanID) else { try fail("TERMINAL_DURABLE_STATE") }
        }
    }
    return frame
}

private func validateExternalAuthorityRoots(
    manifest: [String: Any], authority: String, generations: [String: Any],
    components: [String: Any], evidence: [[String: Any]], _ code: String
) throws -> [String: Any] {
    semanticSection = "EXTERNAL_AUTHORITY"
    let operationEntry = try evidenceEntry(evidence, role: "operation-authority-root", code)
    let passEntry = try evidenceEntry(evidence, role: "vps-pass-root", code)
    let issuerEntry = try evidenceEntry(evidence, role: "vps-issuer-authority-root", code)
    let humanEntry = try evidenceEntry(evidence, role: "human-authorization-root", code)
    let publisherEntry = try evidenceEntry(evidence, role: "publisher-input-manifest-root", code)
    let descriptorEntry = try evidenceEntry(evidence, role: "ssh-trust-descriptor", code)
    let publicKeyEntry = try evidenceEntry(evidence, role: "ssh-public-key", code)
    let fingerprintEntry = try evidenceEntry(evidence, role: "ssh-public-key-fingerprint", code)
    let authorityManifestEntry = try evidenceEntry(evidence, role: "authority-manifest", code)
#if !CI3_SYNTHETIC_TEST
    let authorityRoot = "/Library/Application Support/Agentempp/ci3-controller-authority/\(authority)"
    let fixedRootPaths = [
        "operation-authority-root": "\(authorityRoot)/mac-operation-authority.v1.json",
        "vps-pass-root": "\(authorityRoot)/vps-operation-authority.pass.json",
        "vps-issuer-authority-root": "\(authorityRoot)/vps-issuer-authority.receipt.json",
        "human-authorization-root": "\(authorityRoot)/human-authorization.receipt.json",
        "publisher-input-manifest-root": "\(authorityRoot)/publisher-input.manifest.json",
        "ssh-trust-descriptor": "\(authorityRoot)/ssh-trust-descriptor.json",
        "ssh-public-key": "\(authorityRoot)/ssh-identity.pub",
    ]
    for (role, fixedPath) in fixedRootPaths {
        let entry = try evidenceEntry(evidence, role: role, code)
        guard try string(entry["path"], code) == fixedPath else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }
    }
#endif
    let (_, _, sshDescriptor) = try evidenceObject(evidence, role: "ssh-trust-descriptor", code)
    try exactKeys(sshDescriptor, [
        "authority_sha", "destination_sha256", "host_key_ed25519_fingerprint_sha256",
        "identity_public_key_fingerprint_sha256", "identity_public_key_sha256", "isolated_config_sha256",
        "known_hosts_sha256", "native_key_order", "native_record_count", "native_records_sha256", "purpose",
        "raw_destination_reported", "remote_generation_id", "schema_version", "ssh_code_signature_sha256",
        "ssh_executable_path_sha256", "ssh_executable_sha256", "ssh_version_sha256",
    ], "TERMINAL_SSH_ROOTS")
    let (sshPublicKeyBytes, _) = try readBoundFile(
        try string(publicKeyEntry["path"], code), expected: try dictionary(publicKeyEntry["metadata"], code),
        mode: UInt16(try integer(dictionary(publicKeyEntry["metadata"], code)["mode"], code)), code: "TERMINAL_SSH_ROOTS"
    )
    let (sshFingerprintBytes, _) = try readBoundFile(
        try string(fingerprintEntry["path"], code), expected: try dictionary(fingerprintEntry["metadata"], code),
        mode: UInt16(try integer(dictionary(fingerprintEntry["metadata"], code)["mode"], code)), code: "TERMINAL_SSH_ROOTS"
    )
    let fingerprintProcess = Process()
    fingerprintProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
    fingerprintProcess.arguments = ["-lf", try string(publicKeyEntry["path"], code), "-E", "sha256"]
    fingerprintProcess.environment = ["PATH": "/usr/bin:/bin"]
    let fingerprintOutput = Pipe()
    let fingerprintError = Pipe()
    fingerprintProcess.standardOutput = fingerprintOutput
    fingerprintProcess.standardError = fingerprintError
    try fingerprintProcess.run()
    fingerprintProcess.waitUntilExit()
    let recomputedFingerprint = try fingerprintOutput.fileHandleForReading.readToEnd() ?? Data()
    let recomputedFingerprintError = try fingerprintError.fileHandleForReading.readToEnd() ?? Data()
    guard fingerprintProcess.terminationStatus == 0, recomputedFingerprintError.isEmpty,
          recomputedFingerprint == sshFingerprintBytes else { try fail("TERMINAL_SSH_ROOTS") }
    guard try integer(sshDescriptor["schema_version"], code) == 1,
          try string(sshDescriptor["purpose"], code) == "CI3_MAC_SSH_TRUST_DESCRIPTOR_V1",
          try string(sshDescriptor["authority_sha"], code) == authority,
          try string(sshDescriptor["remote_generation_id"], code) == string(generations["remote"], code),
          try string(sshDescriptor["identity_public_key_sha256"], code) == sha256(sshPublicKeyBytes),
          try string(sshDescriptor["identity_public_key_fingerprint_sha256"], code) == sha256(sshFingerprintBytes),
          try bool(sshDescriptor["raw_destination_reported"], code) == false,
          try string(publicKeyEntry["sha256"], code) == sha256(sshPublicKeyBytes),
          try string(fingerprintEntry["sha256"], code) == sha256(sshFingerprintBytes) else { try fail("TERMINAL_SSH_ROOTS") }

    let (_, _, operation) = try evidenceObject(evidence, role: "operation-authority-root", code)
    try exactKeys(operation, [
        "context", "purpose", "raw_values", "remote", "scans", "schema_version",
        "simulator", "ssh", "worktree", "writer",
    ], code)
    let operationContext = try dictionary(operation["context"], code)
    try exactKeys(operationContext, ["authority", "generations", "remote"], code)
    let operationAuthority = try dictionary(operationContext["authority"], code)
    try exactKeys(operationAuthority, ["commit", "components", "manifest_sha256", "parent", "subject", "tree"], code)
    let operationSSH = try dictionary(operation["ssh"], code)
    guard try integer(operation["schema_version"], code) == 1,
          try string(operation["purpose"], code) == "CI3_MAC_OPERATION_AUTHORITY_V1",
          try string(operationAuthority["commit"], code) == authority,
          try string(operationAuthority["tree"], code) == string(manifest["authority_tree"], code),
          try string(operationAuthority["manifest_sha256"], code) == string(manifest["authority_manifest_sha256"], code),
          try compactJSONBytes(dictionary(operationAuthority["components"], code)) == compactJSONBytes(components),
          try compactJSONBytes(dictionary(operationContext["generations"], code)) == compactJSONBytes(generations),
          try string(operationSSH["trust_descriptor_sha256"], code) == string(descriptorEntry["sha256"], code),
          try string(operationSSH["destination_sha256"], code) == string(sshDescriptor["destination_sha256"], code),
          try string(operationSSH["host_key_ed25519_sha256"], code) == string(sshDescriptor["host_key_ed25519_fingerprint_sha256"], code),
          try string(operationSSH["config_sha256"], code) == string(sshDescriptor["isolated_config_sha256"], code),
          try string(operationSSH["known_hosts_sha256"], code) == string(sshDescriptor["known_hosts_sha256"], code),
          try string(operationSSH["code_signature_sha256"], code) == string(sshDescriptor["ssh_code_signature_sha256"], code),
          try string(operationSSH["executable_path_sha256"], code) == string(sshDescriptor["ssh_executable_path_sha256"], code),
          try string(operationSSH["executable_sha256"], code) == string(sshDescriptor["ssh_executable_sha256"], code),
          try string(operationSSH["version_sha256"], code) == string(sshDescriptor["ssh_version_sha256"], code),
          try string(operationSSH["identity_public_key_sha256"], code) == sha256(sshPublicKeyBytes),
          try string(operationSSH["identity_public_key_fingerprint_sha256"], code) == sha256(sshFingerprintBytes),
          isHex(try string(authorityManifestEntry["sha256"], code), count: 64),
          try bool(operation["raw_values"], code) == false else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }

    _ = try validatedJournalFrame(evidence, code)

    let (_, _, issuer) = try evidenceObject(evidence, role: "vps-issuer-authority-root", code)
    try exactKeys(issuer, [
        "allowed_pass_purpose", "authority_sha", "issuer_generation_id", "issuer_identity_sha256",
        "normal_executor_authorized", "public_key_algorithm", "public_key_raw_base64", "public_key_sha256",
        "purpose", "raw_values", "schema_version",
    ], code)
    guard let issuerKeyBytes = Data(base64Encoded: try string(issuer["public_key_raw_base64"], code)),
          issuerKeyBytes.count == 32,
          try integer(issuer["schema_version"], code) == 1,
          try string(issuer["purpose"], code) == "CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1",
          try string(issuer["authority_sha"], code) == authority,
          isGeneration(try string(issuer["issuer_generation_id"], code), prefix: "issuer"),
          isHex(try string(issuer["issuer_identity_sha256"], code), count: 64),
          try string(issuer["public_key_algorithm"], code) == "Ed25519",
          try string(issuer["public_key_sha256"], code) == sha256(issuerKeyBytes),
          try string(issuer["allowed_pass_purpose"], code) == "CI3_VPS_OPERATION_AUTHORITY_PASS_V1",
          try bool(issuer["normal_executor_authorized"], code) == false,
          try bool(issuer["raw_values"], code) == false else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }

    let (_, _, pass) = try evidenceObject(evidence, role: "vps-pass-root", code)
    try exactKeys(pass, [
        "attempt", "authority_manifest_sha256", "authority_parent", "authority_sha", "authority_subject_sha256",
        "authority_tree", "collector_contracts_sha256", "controller_generation_id", "issuer_authority_sha256",
        "issuer_key_sha256", "node_candidate_sha256", "operation_authority_sha256",
        "publisher_input_manifest_sha256", "purpose", "raw_values", "remote_generation_id", "retry",
        "schema_version", "signature_base64", "signed_payload_sha256", "source_generation_id", "transfer_payload_sha256",
    ], code)
    var signedPayload = pass
    signedPayload.removeValue(forKey: "signed_payload_sha256")
    signedPayload.removeValue(forKey: "signature_base64")
    let signedPayloadBytes = try compactJSONBytes(signedPayload)
    guard let signature = Data(base64Encoded: try string(pass["signature_base64"], code)), signature.count == 64,
          try integer(pass["schema_version"], code) == 1,
          try string(pass["purpose"], code) == "CI3_VPS_OPERATION_AUTHORITY_PASS_V1",
          try string(pass["authority_sha"], code) == authority,
          try string(pass["authority_tree"], code) == string(manifest["authority_tree"], code),
          try string(pass["authority_manifest_sha256"], code) == string(manifest["authority_manifest_sha256"], code),
          try string(pass["operation_authority_sha256"], code) == string(operationEntry["sha256"], code),
          try string(pass["remote_generation_id"], code) == string(generations["remote"], code),
          try string(pass["controller_generation_id"], code) == string(generations["controller"], code),
          try string(pass["issuer_authority_sha256"], code) == string(issuerEntry["sha256"], code),
          try string(pass["issuer_key_sha256"], code) == sha256(issuerKeyBytes),
          try string(pass["authority_parent"], code) == string(operationAuthority["parent"], code),
          try string(pass["authority_subject_sha256"], code) == sha256(Data(string(operationAuthority["subject"], code).utf8)),
          try integer(pass["attempt"], code) == 1, try bool(pass["retry"], code) == false,
          (try string(pass["source_generation_id"], code)).hasPrefix("src-"),
          try string(pass["signed_payload_sha256"], code) == sha256(signedPayloadBytes),
          try Curve25519.Signing.PublicKey(rawRepresentation: issuerKeyBytes).isValidSignature(signature, for: signedPayloadBytes),
          try bool(pass["raw_values"], code) == false else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }

    let (_, _, human) = try evidenceObject(evidence, role: "human-authorization-root", code)
    try exactKeys(human, [
        "approved_action", "attempt", "authority_manifest_sha256", "authority_sha", "node_binary_sha256",
        "operation_authority_sha256", "publisher_input_manifest_sha256", "purpose", "raw_values", "retry",
        "schema_version", "vps_operation_authority_pass_sha256",
    ], code)
    guard try integer(human["schema_version"], code) == 1,
          try string(human["purpose"], code) == "CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V1",
          try string(human["authority_sha"], code) == authority,
          try string(human["approved_action"], code) == "PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY",
          try string(human["authority_manifest_sha256"], code) == string(manifest["authority_manifest_sha256"], code),
          try string(human["operation_authority_sha256"], code) == string(operationEntry["sha256"], code),
          try string(human["publisher_input_manifest_sha256"], code) == string(publisherEntry["sha256"], code),
          try string(human["vps_operation_authority_pass_sha256"], code) == string(passEntry["sha256"], code),
          try string(human["node_binary_sha256"], code) == string(pass["node_candidate_sha256"], code),
          try integer(human["attempt"], code) == 1, try bool(human["retry"], code) == false,
          try bool(human["raw_values"], code) == false else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }

    let (_, _, publisher) = try evidenceObject(evidence, role: "publisher-input-manifest-root", code)
    try exactKeys(publisher, [
        "authority_sha", "collector_contracts_sha256", "controller_generation_id", "entries", "purpose",
        "raw_values", "remote_generation_id", "schema_version", "transfer_payload_sha256",
    ], code)
    let publisherEntries = try array(publisher["entries"], code).map { try dictionary($0, code) }
    let collectorContractsSha256 = try sha256(compactJSONBytes(try dictionary(operation["scans"], code)))
    guard try integer(publisher["schema_version"], code) == 1,
          try string(publisher["purpose"], code) == "CI3_VPS_PUBLISHER_INPUT_MANIFEST_V1",
          try string(publisher["authority_sha"], code) == authority,
          try string(publisher["remote_generation_id"], code) == string(generations["remote"], code),
          try string(publisher["controller_generation_id"], code) == string(generations["controller"], code),
          try string(publisher["collector_contracts_sha256"], code) == collectorContractsSha256,
          try string(pass["collector_contracts_sha256"], code) == collectorContractsSha256,
          publisherEntries.count == 2,
          try string(publisherEntries[0]["role"], code) == "operation-authority",
          try string(publisherEntries[0]["sha256"], code) == string(operationEntry["sha256"], code),
          try string(publisherEntries[1]["role"], code) == "node-runtime",
          try string(publisherEntries[1]["sha256"], code) == string(pass["node_candidate_sha256"], code),
          try string(publisher["transfer_payload_sha256"], code) == sha256(compactJSONArrayBytes(publisherEntries)),
          try string(pass["publisher_input_manifest_sha256"], code) == string(publisherEntry["sha256"], code),
          try string(pass["transfer_payload_sha256"], code) == string(publisher["transfer_payload_sha256"], code),
          try bool(publisher["raw_values"], code) == false else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }

    guard isHex(try string(publisherEntry["sha256"], code), count: 64),
          isHex(try string(humanEntry["sha256"], code), count: 64) else { try fail("TERMINAL_EXTERNAL_AUTHORITY") }
    return operation
}

private func validateSemanticRoots(
    manifest: [String: Any], authority: String, generations: [String: Any],
    components: [String: Any], evidence: [[String: Any]], scans: [[String: Any]], _ code: String
) throws {
    let operation = try validateExternalAuthorityRoots(
        manifest: manifest, authority: authority, generations: generations,
        components: components, evidence: evidence, code
    )
    let operationRemote = try dictionary(operation["remote"], code)
    try exactKeys(operationRemote, ["config_path", "credential_path", "receipt_path"], code)
    let operationContext = try dictionary(operation["context"], code)
    let operationContextRemote = try dictionary(operationContext["remote"], code)
    try exactKeys(operationContextRemote, [
        "bundle_path_sha256", "config_path_sha256", "config_sha256", "credential_path_sha256",
        "credential_sha256", "receipt_path_sha256", "receipt_sha256",
    ], "TERMINAL_REMOTE_ROOTS")
    let remotePaths = [
        "receipt": try string(operationRemote["receipt_path"], code),
        "config": try string(operationRemote["config_path"], code),
        "credential": try string(operationRemote["credential_path"], code),
    ]
    for remotePath in remotePaths.values { _ = try canonicalRemoteCommand(remotePath, code) }
    let operationWriter = try dictionary(operation["writer"], code)
    try exactKeys(operationWriter, ["authority_path", "manifest_path", "phase_target_contracts"], code)
    let phaseTargetContracts = try array(operationWriter["phase_target_contracts"], code).map { try dictionary($0, code) }
    guard phaseTargetContracts.count == controllerEvidencePhases.count else { try fail("TERMINAL_PHASE_TARGET") }
    semanticSection = "AUTHORITY"
    let (authorityEntry, _, literalManifest) = try evidenceObject(evidence, role: "authority-manifest", code)
    try exactKeys(literalManifest, ["components", "entries", "purpose", "raw_values", "schema_version", "source_sha256"], code)
    guard try integer(literalManifest["schema_version"], code) == 1,
          try string(literalManifest["purpose"], code) == "CI3_LITERAL_AUTHORITY_MANIFEST_V1",
          try string(literalManifest["source_sha256"], code) == string(manifest["authority_manifest_sha256"], code),
          try bool(literalManifest["raw_values"], code) == false else { try fail(code) }
    let literalEntries = try array(literalManifest["entries"], code)
    guard literalEntries.count == authorityPaths.count else { try fail(code) }
    var reconstructedAuthorityManifest = ""
    for (index, rawEntry) in literalEntries.enumerated() {
        let entry = try dictionary(rawEntry, code)
        try exactKeys(entry, ["blob_oid", "path", "sha256"], code)
        guard try string(entry["path"], code) == authorityPaths[index],
              isHex(try string(entry["blob_oid"], code), count: 40),
              isHex(try string(entry["sha256"], code), count: 64) else { try fail(code) }
        reconstructedAuthorityManifest += "\(try string(entry["path"], code)) \(try string(entry["blob_oid"], code)) \(try string(entry["sha256"], code))\n"
    }
    guard try sha256(Data(reconstructedAuthorityManifest.utf8)) == string(literalManifest["source_sha256"], code) else { try fail(code) }
    let literalComponents = try dictionary(literalManifest["components"], code)
    try exactKeys(literalComponents, componentNames, code)
    for name in componentNames {
        let expected = try dictionary(components[name], code)
        let actual = try dictionary(literalComponents[name], code)
        guard try string(actual["path"], code) == string(expected["path"], code),
              try string(actual["blob_oid"], code) == string(expected["blob_oid"], code),
              try string(actual["sha256"], code) == string(expected["sha256"], code) else { try fail(code) }
    }
    let (_, _, attestation) = try evidenceObject(evidence, role: "launch-attestation", code)
    try exactKeys(attestation, ["authority_manifest_sha256", "authority_parent", "authority_sha", "authority_subject_sha256", "authority_tree", "components", "purpose", "raw_values", "schema_version", "tools"], code)
    guard try integer(attestation["schema_version"], code) == 1,
          try string(attestation["purpose"], code) == "CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2",
          try string(attestation["authority_sha"], code) == authority,
          try string(attestation["authority_tree"], code) == string(manifest["authority_tree"], code),
          try string(attestation["authority_manifest_sha256"], code) == string(manifest["authority_manifest_sha256"], code),
          isHex(try string(attestation["authority_parent"], code), count: 40),
          isHex(try string(attestation["authority_subject_sha256"], code), count: 64),
          try bool(attestation["raw_values"], code) == false else { try fail(code) }
    let attestationComponents = try dictionary(attestation["components"], code)
    for name in componentNames {
        let expected = try dictionary(components[name], code)
        let actual = try dictionary(attestationComponents[name], code)
        guard try string(actual["path"], code) == string(expected["path"], code),
              try string(actual["blob_oid"], code) == string(expected["blob_oid"], code),
              try string(actual["sha256"], code) == string(expected["sha256"], code) else { try fail(code) }
    }
    let tools = try dictionary(attestation["tools"], code)
    try exactKeys(tools, ["node", "ssh", "swiftc", "xcodebuild"], code)
    for name in ["node", "ssh", "swiftc", "xcodebuild"] {
        let tool = try dictionary(tools[name], code)
        try exactKeys(tool, ["binary_sha256", "path_sha256", "version_sha256"], code)
        guard isHex(try string(tool["binary_sha256"], code), count: 64),
              isHex(try string(tool["path_sha256"], code), count: 64),
              isHex(try string(tool["version_sha256"], code), count: 64) else { try fail(code) }
    }
    guard isHex(try string(authorityEntry["sha256"], code), count: 64) else { try fail(code) }

    semanticSection = "BOOTSTRAP"
    let (bootstrapEntry, _, bootstrap) = try evidenceObject(evidence, role: "bootstrap-claim", code)
    try exactKeys(bootstrap, [
        "attempt", "authority_manifest_sha256", "authority_sha", "components", "controller_generation_id",
        "raw_values", "remote_bundle_path_sha256", "remote_generation_id", "remote_receipt_path_sha256", "retry",
        "schema_version", "simulator_gate_sha256", "simulator_generation_id", "ssh_code_signature_sha256",
        "ssh_effective_config_sha256", "ssh_executable_sha256", "ssh_trust_descriptor_sha256",
        "terminal_generation_id", "purpose",
    ], code)
    guard try string(bootstrapEntry["sha256"], code) == string(manifest["bootstrap_claim_sha256"], code),
          try integer(bootstrap["schema_version"], code) == 1,
          try string(bootstrap["purpose"], code) == "CI3_MAC_BRIDGE_BOOTSTRAP_CLAIM_V1",
          try string(bootstrap["authority_sha"], code) == authority,
          try string(bootstrap["authority_manifest_sha256"], code) == string(manifest["authority_manifest_sha256"], code),
          try string(bootstrap["controller_generation_id"], code) == string(generations["controller"], code),
          try string(bootstrap["remote_generation_id"], code) == string(generations["remote"], code),
          try string(bootstrap["simulator_generation_id"], code) == string(generations["simulator"], code),
          try string(bootstrap["terminal_generation_id"], code) == string(generations["terminal"], code),
          try string(bootstrap["remote_bundle_path_sha256"], code) == sha256(Data(((remotePaths["config"]! as NSString).deletingLastPathComponent).utf8)),
          try string(bootstrap["remote_receipt_path_sha256"], code) == sha256(Data(remotePaths["receipt"]!.utf8)),
          try integer(bootstrap["attempt"], code) == 1, try bool(bootstrap["retry"], code) == false,
          try bool(bootstrap["raw_values"], code) == false else { try fail(code) }
    for field in ["remote_bundle_path_sha256", "remote_receipt_path_sha256", "simulator_gate_sha256", "ssh_code_signature_sha256", "ssh_effective_config_sha256", "ssh_executable_sha256", "ssh_trust_descriptor_sha256"] {
        guard isHex(try string(bootstrap[field], code), count: 64) else { try fail(code) }
    }
    let bootstrapComponents = try dictionary(bootstrap["components"], code)
    try exactKeys(bootstrapComponents, componentNames, code)
    for name in componentNames {
        guard try compactJSONBytes(dictionary(bootstrapComponents[name], code)) == compactJSONBytes(dictionary(components[name], code)) else { try fail(code) }
    }

    semanticSection = "READS"
    let readRoles = [
        "receipt-read-claim", "receipt-read-result", "config-read-claim",
        "config-read-result", "credential-read-claim", "credential-read-result",
    ]
    var readHashes: [String] = []
    var claims: [String: (String, [String: Any])] = [:]
    var readResults: [String: (String, [String: Any])] = [:]
    for role in readRoles {
        let (entry, _, object) = try evidenceObject(evidence, role: role, code)
        let hash = try string(entry["sha256"], code)
        readHashes.append(hash)
        let kind = try string(object["kind"], code)
        if role.hasSuffix("claim") {
            try exactKeys(object, ["attempt", "bootstrap_claim_sha256", "expected_path_sha256", "expected_sha256", "kind", "purpose", "raw_values", "remote_generation_id", "retry", "schema_version", "ssh_effective_config_sha256", "ssh_executable_sha256", "ssh_trust_descriptor_sha256"], code)
            guard try integer(object["schema_version"], code) == 1,
                  try string(object["purpose"], code) == "CI3_MAC_BRIDGE_READ_CLAIM_V1",
                  try string(object["bootstrap_claim_sha256"], code) == string(bootstrapEntry["sha256"], code),
                  ["receipt", "config", "credential"].contains(kind),
                  try string(object["expected_path_sha256"], code) == sha256(Data(remotePaths[kind]!.utf8)),
                  isHex(try string(object["expected_sha256"], code), count: 64),
                  isHex(try string(object["ssh_executable_sha256"], code), count: 64),
                  isHex(try string(object["ssh_effective_config_sha256"], code), count: 64),
                  isHex(try string(object["ssh_trust_descriptor_sha256"], code), count: 64),
                  try integer(object["attempt"], code) == 1, try bool(object["retry"], code) == false,
                  try bool(object["raw_values"], code) == false else { try fail(code) }
            if kind == "receipt" {
                guard object["remote_generation_id"] is NSNull else { try fail(code) }
            } else {
                guard try string(object["remote_generation_id"], code) == string(generations["remote"], code) else { try fail(code) }
            }
            claims[kind] = (hash, object)
        } else {
            try exactKeys(object, ["bytes", "capture_identity_sha256", "capture_sha256", "claim_sha256", "descriptor_read", "exit", "finished_at", "kind", "purpose", "raw_values", "remote_command_sha256", "remote_generation_id", "schema_version", "started_at", "stderr_class", "ssh_effective_config_sha256", "ssh_trust_descriptor_sha256"], code)
            guard try integer(object["schema_version"], code) == 1,
                  try string(object["purpose"], code) == "CI3_MAC_BRIDGE_READ_RESULT_V1",
                  let claim = claims[kind], try string(object["claim_sha256"], code) == claim.0,
                  try string(object["capture_sha256"], code) == string(claim.1["expected_sha256"], code),
                  try string(object["remote_generation_id"], code) == string(generations["remote"], code),
                  try bool(object["descriptor_read"], code), try integer(object["exit"], code) == 0,
                  try integer(object["bytes"], code) > 0, try string(object["stderr_class"], code) == "EMPTY",
                  isUTCTimestamp(try string(object["started_at"], code)), isUTCTimestamp(try string(object["finished_at"], code)),
                  try string(object["ssh_effective_config_sha256"], code) == string(claim.1["ssh_effective_config_sha256"], code),
                  try string(object["ssh_trust_descriptor_sha256"], code) == string(claim.1["ssh_trust_descriptor_sha256"], code),
                  try string(object["remote_command_sha256"], code) == sha256(Data(canonicalRemoteCommand(remotePaths[kind]!, code).utf8)),
                  try bool(object["raw_values"], code) == false else { try fail(code) }
            for field in ["capture_identity_sha256", "capture_sha256", "remote_command_sha256"] {
                guard isHex(try string(object[field], code), count: 64) else { try fail(code) }
            }
            readResults[kind] = (hash, object)
        }
    }
    guard try sha256(Data(readHashes.joined(separator: ":").utf8)) == string(manifest["claim_result_chain_sha256"], code) else { try fail(code) }

    semanticSection = "REMOTE"
    let (remoteEntry, _, remoteReceipt) = try evidenceObject(evidence, role: "remote-receipt", code)
    try exactKeys(remoteReceipt, [
        "anchor_writer_blob_oid", "anchor_writer_file_sha256", "authority_commit", "authority_parent", "authority_subject", "authority_tree", "authority_tree_manifest_sha256",
        "cleanup_deadline", "controller_blob_oid", "controller_file_sha256", "created_at_utc", "credential_source_path", "credential_source_sha256", "deployment_receipt_sha256",
        "env_development_count", "env_preview_count", "env_production_count", "env_receipt_sha256", "env_source_sha256", "generator_blob_sha", "generator_file_sha256",
        "implementation_sha", "launcher_blob_oid", "launcher_file_sha256", "output_config_sha256", "output_filenames", "preview_deployment_count", "primary_opened",
        "production_deployment_count", "provisioning_receipt_sha256", "purpose", "raw_values_reported", "remote_bundle_generation_id", "remote_bundle_immutable", "schema_version",
        "service_role_emitted", "source_env_descriptor_identity_sha256", "source_generation_id", "sso_state", "staging_project_ref", "terminal_scan_ids", "token_emitted",
    ], code)
    guard try string(remoteEntry["sha256"], code) == string(manifest["remote_bundle_sha256"], code),
          try integer(remoteReceipt["schema_version"], code) == 1,
          try string(remoteReceipt["purpose"], code) == "VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1",
          try string(remoteReceipt["authority_commit"], code) == authority,
          try string(remoteReceipt["authority_parent"], code) == string(attestation["authority_parent"], code),
          try sha256(Data(string(remoteReceipt["authority_subject"], code).utf8)) == string(attestation["authority_subject_sha256"], code),
          try string(remoteReceipt["authority_tree"], code) == string(manifest["authority_tree"], code),
          try string(remoteReceipt["authority_tree_manifest_sha256"], code) == string(manifest["authority_manifest_sha256"], code),
          try string(remoteReceipt["remote_bundle_generation_id"], code) == string(generations["remote"], code),
          isGeneration(try string(remoteReceipt["source_generation_id"], code), prefix: "src"),
          try integer(remoteReceipt["preview_deployment_count"], code) == 1,
          try integer(remoteReceipt["production_deployment_count"], code) == 0,
          try integer(remoteReceipt["env_preview_count"], code) == 3,
          try integer(remoteReceipt["env_production_count"], code) == 0,
          try integer(remoteReceipt["env_development_count"], code) == 0,
          remoteReceipt["sso_state"] is NSNull,
          try bool(remoteReceipt["service_role_emitted"], code) == false,
          try bool(remoteReceipt["token_emitted"], code) == false,
          try bool(remoteReceipt["raw_values_reported"], code) == false,
          try bool(remoteReceipt["primary_opened"], code) == false,
          try bool(remoteReceipt["remote_bundle_immutable"], code),
          (try array(remoteReceipt["terminal_scan_ids"], code).compactMap { $0 as? String }) == scanIDs,
          isUTCTimestamp(try string(remoteReceipt["created_at_utc"], code)),
          isUTCTimestamp(try string(remoteReceipt["cleanup_deadline"], code)) else { try fail(code) }
    for field in ["generator_blob_sha", "controller_blob_oid", "launcher_blob_oid", "anchor_writer_blob_oid"] {
        guard isHex(try string(remoteReceipt[field], code), count: 40) else { try fail(code) }
    }
    for field in ["generator_file_sha256", "controller_file_sha256", "launcher_file_sha256", "anchor_writer_file_sha256", "source_env_descriptor_identity_sha256", "env_source_sha256", "env_receipt_sha256", "deployment_receipt_sha256", "credential_source_sha256", "provisioning_receipt_sha256", "output_config_sha256"] {
        guard isHex(try string(remoteReceipt[field], code), count: 64) else { try fail(code) }
    }
    for (name, oidField, hashField) in [("generator", "generator_blob_sha", "generator_file_sha256"), ("controller", "controller_blob_oid", "controller_file_sha256"), ("launcher", "launcher_blob_oid", "launcher_file_sha256"), ("writer", "anchor_writer_blob_oid", "anchor_writer_file_sha256")] {
        let component = try dictionary(components[name], code)
        guard try string(remoteReceipt[oidField], code) == string(component["blob_oid"], code),
              try string(remoteReceipt[hashField], code) == string(component["sha256"], code) else { try fail(code) }
    }
    guard (try array(remoteReceipt["output_filenames"], code).compactMap { $0 as? String }) == ["mobile-staging-config.json", "bridge.receipt.json"] else { try fail(code) }
    guard let receiptRead = readResults["receipt"], let configRead = readResults["config"], let credentialRead = readResults["credential"],
          try string(receiptRead.1["capture_sha256"], code) == string(remoteEntry["sha256"], code),
          try string(configRead.1["capture_sha256"], code) == string(remoteReceipt["output_config_sha256"], code),
          try string(credentialRead.1["capture_sha256"], code) == string(remoteReceipt["credential_source_sha256"], code),
          try string(operationContextRemote["receipt_sha256"], code) == string(remoteEntry["sha256"], code),
          try string(operationContextRemote["config_sha256"], code) == string(remoteReceipt["output_config_sha256"], code),
          try string(operationContextRemote["credential_sha256"], code) == string(remoteReceipt["credential_source_sha256"], code) else { try fail("TERMINAL_REMOTE_ROOTS") }

    semanticSection = "LOCAL"
    let (localEntry, _, localReceipt) = try evidenceObject(evidence, role: "local-receipt", code)
    semanticSection = "LOCAL_FIELDS"
    try exactKeys(localReceipt, ["authority_sha", "bootstrap_claim_sha256", "components", "config_sha256", "credential_sha256", "generations", "purpose", "raw_values", "read_claim_chain_sha256", "read_result_chain_sha256", "remote_receipt_sha256", "schema_version", "simulator_gate_sha256", "ssh_provenance_sha256", "terminal_scan_ids", "terminal_state"], code)
    guard try string(localEntry["sha256"], code) == string(manifest["local_bundle_sha256"], code),
          try integer(localReceipt["schema_version"], code) == 1,
          try string(localReceipt["purpose"], code) == "CI3_LOCAL_BRIDGE_RECEIPT_V1",
          try string(localReceipt["authority_sha"], code) == authority,
          try string(localReceipt["bootstrap_claim_sha256"], code) == string(bootstrapEntry["sha256"], code),
          try string(localReceipt["remote_receipt_sha256"], code) == string(remoteEntry["sha256"], code),
          try compactJSONBytes(dictionary(localReceipt["components"], code)) == compactJSONBytes(components),
          try compactJSONBytes(dictionary(localReceipt["generations"], code)) == compactJSONBytes(generations),
          (try array(localReceipt["terminal_scan_ids"], code).compactMap { $0 as? String }) == scanIDs,
          try string(localReceipt["terminal_state"], code) == "PENDING_INSTALL_AND_SCANS",
          try bool(localReceipt["raw_values"], code) == false else { try fail(code) }
    for field in ["config_sha256", "credential_sha256", "read_claim_chain_sha256", "read_result_chain_sha256", "simulator_gate_sha256", "ssh_provenance_sha256"] {
        guard isHex(try string(localReceipt[field], code), count: 64) else { try fail(code) }
    }
    semanticSection = "LOCAL_CHAIN"
    let orderedClaims = ["receipt", "config", "credential"].map { claims[$0]!.1 }
    let orderedResults = ["receipt", "config", "credential"].map { readResults[$0]!.1 }
    guard try string(localReceipt["read_claim_chain_sha256"], code) == sha256(compactJSONArrayBytes(orderedClaims)),
          try string(localReceipt["read_result_chain_sha256"], code) == sha256(compactJSONArrayBytes(orderedResults)),
          try string(localReceipt["config_sha256"], code) == string(readResults["config"]!.1["capture_sha256"], code),
          try string(localReceipt["credential_sha256"], code) == string(readResults["credential"]!.1["capture_sha256"], code) else { try fail(code) }

    semanticSection = "SSH"
    let (sshEntry, _, sshEvent) = try evidenceObject(evidence, role: "ssh-provenance", code)
    try exactKeys(sshEvent, ["event", "result", "result_sha256", "state"], code)
    let sshResult = try dictionary(sshEvent["result"], code)
    try exactKeys(sshResult, ["provenance"], code)
    let sshProvenance = try dictionary(sshResult["provenance"], code)
    let (_, _, sshDescriptor) = try evidenceObject(evidence, role: "ssh-trust-descriptor", code)
    let publicKeyRoot = try evidenceEntry(evidence, role: "ssh-public-key", code)
    let fingerprintRoot = try evidenceEntry(evidence, role: "ssh-public-key-fingerprint", code)
    try exactKeys(sshProvenance, ["code_signature_sha256", "config_sha256", "destination_sha256", "effective_config_sha256", "executable_sha256", "host_key_ed25519_sha256", "identity_public_key_fingerprint_sha256", "identity_public_key_sha256", "known_hosts_sha256", "trust_descriptor_sha256", "version_sha256"], code)
    guard try string(sshEntry["sha256"], code) == string(manifest["ssh_provenance_sha256"], code),
          try string(sshEvent["event"], code) == "VERIFY_SSH", try string(sshEvent["state"], code) == "SSH_VERIFIED",
          try string(sshEvent["result_sha256"], code) == sha256(try compactJSONBytes(sshResult)),
          try string(bootstrap["ssh_executable_sha256"], code) == string(sshProvenance["executable_sha256"], code),
          try string(bootstrap["ssh_effective_config_sha256"], code) == string(sshProvenance["effective_config_sha256"], code),
          try string(bootstrap["ssh_trust_descriptor_sha256"], code) == string(sshProvenance["trust_descriptor_sha256"], code),
          try string(sshProvenance["trust_descriptor_sha256"], code) == string(evidenceEntry(evidence, role: "ssh-trust-descriptor", code)["sha256"], code),
          try string(sshProvenance["identity_public_key_sha256"], code) == string(sshDescriptor["identity_public_key_sha256"], code),
          try string(sshProvenance["identity_public_key_sha256"], code) == string(publicKeyRoot["sha256"], code),
          try string(sshProvenance["identity_public_key_fingerprint_sha256"], code) == string(sshDescriptor["identity_public_key_fingerprint_sha256"], code),
          try string(sshProvenance["identity_public_key_fingerprint_sha256"], code) == string(fingerprintRoot["sha256"], code),
          try string(localReceipt["ssh_provenance_sha256"], code) == string(sshEntry["sha256"], code),
          try string(sshProvenance["identity_public_key_sha256"], code) != string(sshProvenance["identity_public_key_fingerprint_sha256"], code) else { try fail(code) }
    for value in sshProvenance.values { guard isHex(try string(value, code), count: 64) else { try fail(code) } }
    semanticSection = "SIMULATOR_GATE"
    let (simulatorEntry, _, simulatorEvent) = try evidenceObject(evidence, role: "simulator-gate", code)
    try exactKeys(simulatorEvent, ["event", "result", "result_sha256", "state"], code)
    guard try string(simulatorEntry["sha256"], code) == string(manifest["simulator_gate_sha256"], code),
          try string(simulatorEvent["event"], code) == "VERIFY_SIMULATOR",
          try string(simulatorEvent["state"], code) == "SIMULATOR_VERIFIED" else { try fail(code) }
    let simulatorResult = try dictionary(simulatorEvent["result"], code)
    try exactKeys(simulatorResult, ["receipt"], code)
    guard try string(simulatorEvent["result_sha256"], code) == sha256(try compactJSONBytes(simulatorResult)) else { try fail(code) }
    let simulatorReceipt = try dictionary(simulatorResult["receipt"], code)
    try exactKeys(simulatorReceipt, ["app_installation_sha256", "attempts", "authority_sha", "bundle_id", "container_identity_sha256", "controller_generation_id", "device_selection_sha256", "phase_receipt_hashes", "phases", "probe_ack_sha256", "probe_config_sha256", "probe_credential_sha256", "purpose", "raw_container_path_reported", "removal_proof_sha256", "runtime_sha256", "schema_version", "simulator_generation_id", "source_commit", "terminal_state"], code)
    guard try integer(simulatorReceipt["schema_version"], code) == 1,
          try string(simulatorReceipt["purpose"], code) == "CI3_SIMULATOR_GATE_RECEIPT_V2",
          try string(simulatorReceipt["authority_sha"], code) == authority,
          try string(simulatorReceipt["controller_generation_id"], code) == string(generations["controller"], code),
          try string(simulatorReceipt["simulator_generation_id"], code) == string(generations["simulator"], code),
          try string(simulatorReceipt["bundle_id"], code) == "com.bodyflow.app",
          try string(simulatorReceipt["terminal_state"], code) == "SIMULATOR_GATE_PASS",
          try string(simulatorReceipt["source_commit"], code) == ci3SourceCommit,
          try bool(simulatorReceipt["raw_container_path_reported"], code) == false,
          (try array(simulatorReceipt["phases"], code).compactMap { $0 as? String }) == simulatorPhases else { try fail(code) }
    for field in ["app_installation_sha256", "container_identity_sha256", "device_selection_sha256", "probe_ack_sha256", "probe_config_sha256", "probe_credential_sha256", "removal_proof_sha256", "runtime_sha256"] {
        guard isHex(try string(simulatorReceipt[field], code), count: 64) else { try fail(code) }
    }
    guard isHex(try string(simulatorReceipt["source_commit"], code), count: 40) else { try fail(code) }
    guard try string(bootstrap["simulator_gate_sha256"], code) == string(simulatorEntry["sha256"], code),
          try string(localReceipt["simulator_gate_sha256"], code) == string(simulatorEntry["sha256"], code),
          try string(simulatorReceipt["probe_config_sha256"], code) == string(readResults["config"]!.1["capture_sha256"], code),
          try string(simulatorReceipt["probe_credential_sha256"], code) == string(readResults["credential"]!.1["capture_sha256"], code) else { try fail(code) }
    let attempts = try dictionary(simulatorReceipt["attempts"], code)
    try exactKeys(attempts, ["ack", "install", "launch", "remove", "reobserve", "resolve", "select"], code)
    guard attempts.values.allSatisfy({ ($0 as? NSNumber)?.intValue == 1 }) else { try fail(code) }
    semanticSection = "INSTALL"
    let (installEntry, _, installReceipt) = try evidenceObject(evidence, role: "simulator-install", code)
    try exactKeys(installReceipt, ["authority_sha", "controller_generation_id", "files", "install_claim_sha256", "install_executable_sha256", "local_bundle_sha256", "purpose", "raw_values", "schema_version", "simulator_generation_id"], code)
    guard try string(installEntry["sha256"], code) == string(manifest["simulator_install_sha256"], code),
          try integer(installReceipt["schema_version"], code) == 1,
          try string(installReceipt["purpose"], code) == "CI3_SIMULATOR_INSTALL_RECEIPT_V1",
          try string(installReceipt["authority_sha"], code) == authority,
          try string(installReceipt["controller_generation_id"], code) == string(generations["controller"], code),
          try string(installReceipt["simulator_generation_id"], code) == string(generations["simulator"], code),
          try string(installReceipt["local_bundle_sha256"], code) == string(manifest["local_bundle_sha256"], code),
          isHex(try string(installReceipt["install_claim_sha256"], code), count: 64),
          isHex(try string(installReceipt["install_executable_sha256"], code), count: 64),
          try bool(installReceipt["raw_values"], code) == false else { try fail(code) }
    let installedFiles = try array(installReceipt["files"], code)
    guard installedFiles.count == 2 else { try fail(code) }
    var installedByName: [String: [String: Any]] = [:]
    for rawFile in installedFiles {
        let file = try dictionary(rawFile, code)
        try exactKeys(file, ["dev", "gid", "ino", "mode", "mtime_ns", "name_sha256", "nlink", "sha256", "size", "uid"], code)
        guard isHex(try string(file["name_sha256"], code), count: 64), isHex(try string(file["sha256"], code), count: 64),
              try integer(file["mode"], code) == 0o600, try integer(file["nlink"], code) == 1,
              try integer(file["size"], code) > 0 else { try fail(code) }
        _ = try string(file["dev"], code); _ = try string(file["ino"], code); _ = try string(file["mtime_ns"], code)
        let nameHash = try string(file["name_sha256"], code)
        guard installedByName[nameHash] == nil else { try fail(code) }
        installedByName[nameHash] = file
    }
    let configNameHash = try sha256(Data("mobile-staging-config.json".utf8))
    let credentialNameHash = try sha256(Data("synthetic-patient.credentials.json".utf8))
    guard let installedConfig = installedByName[configNameHash], let installedCredential = installedByName[credentialNameHash],
          try string(installedConfig["sha256"], code) == string(localReceipt["config_sha256"], code),
          try string(installedCredential["sha256"], code) == string(localReceipt["credential_sha256"], code) else { try fail(code) }

    semanticSection = "INPUT_MANIFEST"
    let (inputEntry, _, inputManifest) = try evidenceObject(evidence, role: "input-manifest", code)
    try exactKeys(inputManifest, [
        "authority_sha", "controller_generation_id", "local_bundle_sha256", "purpose", "raw_values",
        "read_commands", "scan_contracts", "scan_ids", "schema_version", "simulator_install_sha256",
        "terminal_generation_id",
    ], code)
    guard try integer(inputManifest["schema_version"], code) == 1,
          try string(inputManifest["purpose"], code) == "CI3_TERMINAL_INPUT_MANIFEST_V1",
          try string(inputManifest["authority_sha"], code) == authority,
          try string(inputManifest["controller_generation_id"], code) == string(generations["controller"], code),
          try string(inputManifest["terminal_generation_id"], code) == string(generations["terminal"], code),
          try string(inputManifest["local_bundle_sha256"], code) == string(manifest["local_bundle_sha256"], code),
          try string(inputManifest["simulator_install_sha256"], code) == string(manifest["simulator_install_sha256"], code),
          (try array(inputManifest["scan_ids"], code).compactMap { $0 as? String }) == scanIDs,
          try bool(inputManifest["raw_values"], code) == false else { try fail(code) }
    let readCommands = try array(inputManifest["read_commands"], code)
    guard readCommands.count == 3 else { try fail(code) }
    for (index, kind) in ["receipt", "config", "credential"].enumerated() {
        let command = try dictionary(readCommands[index], code)
        try exactKeys(command, ["capture_sha256", "expected_path_sha256", "expected_sha256", "kind", "remote_command_sha256"], code)
        guard try string(command["kind"], code) == kind,
              try string(command["expected_path_sha256"], code) == string(claims[kind]!.1["expected_path_sha256"], code),
              try string(command["expected_sha256"], code) == string(claims[kind]!.1["expected_sha256"], code),
              try string(command["capture_sha256"], code) == string(readResults[kind]!.1["capture_sha256"], code),
              try string(command["remote_command_sha256"], code) == string(readResults[kind]!.1["remote_command_sha256"], code) else { try fail(code) }
    }
    let scanContracts = try array(inputManifest["scan_contracts"], code)
    guard scanContracts.count == scanIDs.count else { try fail(code) }
    var scanContractsByID: [String: [String: Any]] = [:]
    for (index, scanID) in scanIDs.enumerated() {
        let contract = try dictionary(scanContracts[index], code)
        try exactKeys(contract, ["collector_version", "contract_sha256", "format", "id", "source_role", "tool_sha256"], code)
        guard try string(contract["id"], code) == scanID,
              try string(contract["tool_sha256"], code) == string(dictionary(components["controller"], code)["sha256"], code),
              try string(contract["contract_sha256"], code) == scannerSchemaHashes[scanID],
              !(try string(contract["collector_version"], code)).isEmpty,
              !(try string(contract["format"], code)).isEmpty,
              !(try string(contract["source_role"], code)).isEmpty else { try fail(code) }
        scanContractsByID[scanID] = contract
    }

    semanticSection = "SIMULATOR_PHASES"
    var predecessor = String(repeating: "0", count: 64)
    for phase in simulatorPhases {
        let prefix = evidencePrefix("simulator", phase)
        let (claimEntry, _, claim) = try evidenceObject(evidence, role: "\(prefix)-claim", code)
        try exactKeys(claim, ["attempt", "authority_sha", "controller_generation_id", "phase", "predecessor_result_sha256", "purpose", "raw_values", "retry", "schema_version", "simulator_generation_id"], code)
        guard try integer(claim["schema_version"], code) == 1,
              try string(claim["purpose"], code) == "CI3_SIMULATOR_PHASE_CLAIM_V1",
              try string(claim["phase"], code) == phase,
              try string(claim["authority_sha"], code) == authority,
              try string(claim["controller_generation_id"], code) == string(generations["controller"], code),
              try string(claim["simulator_generation_id"], code) == string(generations["simulator"], code),
              try string(claim["predecessor_result_sha256"], code) == predecessor,
              try integer(claim["attempt"], code) == 1, try bool(claim["retry"], code) == false,
              try bool(claim["raw_values"], code) == false else { try fail(code) }
        let (receiptEntry, _, receipt) = try evidenceObject(evidence, role: "\(prefix)-receipt", code)
        try exactKeys(receipt, ["claim_sha256", "observation", "observation_sha256", "phase", "physical_reobservation", "purpose", "raw_values", "schema_version"], code)
        let observation = try dictionary(receipt["observation"], code)
        guard try integer(receipt["schema_version"], code) == 1,
              try string(receipt["purpose"], code) == "CI3_SIMULATOR_PHASE_RECEIPT_V1",
              try string(receipt["phase"], code) == phase,
              try string(receipt["claim_sha256"], code) == string(claimEntry["sha256"], code),
              try string(receipt["observation_sha256"], code) == sha256(try compactJSONBytes(observation)),
              try bool(receipt["physical_reobservation"], code), try bool(receipt["raw_values"], code) == false else { try fail(code) }
        if phase == "SELECT_DEVICE" {
            try exactKeys(observation, ["device_selection_sha256"], code)
            guard try string(observation["device_selection_sha256"], code) == string(simulatorReceipt["device_selection_sha256"], code) else { try fail(code) }
        } else if phase == "RESOLVE_CONTAINER" {
            try exactKeys(observation, ["app_installation_sha256", "container_identity_sha256", "runtime_sha256"], code)
            guard try string(observation["app_installation_sha256"], code) == string(simulatorReceipt["app_installation_sha256"], code),
                  try string(observation["container_identity_sha256"], code) == string(simulatorReceipt["container_identity_sha256"], code),
                  try string(observation["runtime_sha256"], code) == string(simulatorReceipt["runtime_sha256"], code) else { try fail(code) }
        } else if phase == "INSTALL_PROBE" {
            try exactKeys(observation, ["config_sha256", "credential_sha256"], code)
            guard try string(observation["config_sha256"], code) == string(simulatorReceipt["probe_config_sha256"], code),
                  try string(observation["credential_sha256"], code) == string(simulatorReceipt["probe_credential_sha256"], code) else { try fail(code) }
        } else if phase == "LAUNCH_PROBE" {
            try exactKeys(observation, ["launch_contract_sha256"], code)
            let launchContract: [String: Any] = ["bundle": "com.bodyflow.app", "device": try string(simulatorReceipt["device_selection_sha256"], code)]
            guard try string(observation["launch_contract_sha256"], code) == sha256(try compactJSONBytes(launchContract)) else { try fail(code) }
        } else if phase == "ACK_PROBE" {
            try exactKeys(observation, ["probe_ack_sha256"], code)
            guard try string(observation["probe_ack_sha256"], code) == string(simulatorReceipt["probe_ack_sha256"], code) else { try fail(code) }
        } else if phase == "REMOVE_PROBE" {
            try exactKeys(observation, ["controller_files_removed", "credential_absent"], code)
            guard try bool(observation["controller_files_removed"], code), try bool(observation["credential_absent"], code) else { try fail(code) }
        } else if phase == "REOBSERVE" {
            try exactKeys(observation, ["ack_absent", "config_absent", "credential_absent"], code)
            guard try bool(observation["ack_absent"], code), try bool(observation["config_absent"], code), try bool(observation["credential_absent"], code) else { try fail(code) }
        }
        let (resultEntry, _, result) = try evidenceObject(evidence, role: "\(prefix)-result", code)
        try exactKeys(result, ["claim_sha256", "observation", "phase", "physical_observation_sha256", "purpose", "raw_values", "receipt_sha256", "schema_version", "terminal_state"], code)
        guard try integer(result["schema_version"], code) == 1,
              try string(result["purpose"], code) == "CI3_SIMULATOR_PHASE_RESULT_V1",
              try string(result["phase"], code) == phase,
              try string(result["claim_sha256"], code) == string(claimEntry["sha256"], code),
              try string(result["receipt_sha256"], code) == string(receiptEntry["sha256"], code),
              try string(result["physical_observation_sha256"], code) == string(receipt["observation_sha256"], code),
              try string(result["terminal_state"], code) == "PHASE_SETTLED",
              try bool(result["raw_values"], code) == false,
              try compactJSONBytes(try dictionary(result["observation"], code)) == compactJSONBytes(observation) else { try fail(code) }
        predecessor = try string(resultEntry["sha256"], code)
    }
    let gatePhaseHashes = try array(simulatorReceipt["phase_receipt_hashes"], code).compactMap { $0 as? String }
    let observedPhaseHashes = try simulatorPhases.map { phase in
        let (entry, _, _) = try evidenceObject(evidence, role: "\(evidencePrefix("simulator", phase))-receipt", code)
        return try string(entry["sha256"], code)
    }
    guard gatePhaseHashes == observedPhaseHashes else { try fail(code) }

    semanticSection = "CONTROLLER_PHASES"
    var controllerPredecessor = String(repeating: "0", count: 64)
    for (phaseIndex, phase) in controllerEvidencePhases.enumerated() {
        semanticSection = "CONTROLLER_PHASE_\(phase)"
        let prefix = evidencePrefix("controller", phase)
        semanticSection = "CONTROLLER_PHASE_\(phase)_CLAIM"
        let (claimEntry, _, claim) = try evidenceObject(evidence, role: "\(prefix)-claim", code)
        try exactKeys(claim, ["attempt", "authority_sha", "contract_sha256", "controller_generation_id", "phase", "predecessor_result_sha256", "purpose", "raw_values", "retry", "schema_version"], code)
        guard try integer(claim["schema_version"], code) == 1,
              try string(claim["purpose"], code) == "CI3_MAC_PHASE_CLAIM_V1",
              try string(claim["phase"], code) == phase,
              try string(claim["authority_sha"], code) == authority,
              try string(claim["controller_generation_id"], code) == string(generations["controller"], code),
              try string(claim["predecessor_result_sha256"], code) == controllerPredecessor,
              try integer(claim["attempt"], code) == 1, try bool(claim["retry"], code) == false,
              try bool(claim["raw_values"], code) == false else { try fail(code) }
        let contract: [String: Any] = [
            "event": phase, "authority_sha": authority,
            "controller_generation_id": try string(generations["controller"], code),
            "generations": generations, "predecessor_result_sha256": controllerPredecessor,
        ]
        guard try string(claim["contract_sha256"], code) == sha256(try compactJSONBytes(contract)) else { try fail(code) }
        semanticSection = "CONTROLLER_PHASE_\(phase)_RECEIPT"
        let (receiptEntry, _, receipt) = try evidenceObject(evidence, role: "\(prefix)-receipt", code)
        try exactKeys(receipt, ["claim_sha256", "observation", "phase", "purpose", "raw_values", "result", "result_sha256", "schema_version"], code)
        let physicalObservation = try dictionary(receipt["observation"], code)
        semanticSection = "CONTROLLER_PHASE_\(phase)_OBSERVATION_FIELDS"
        try exactKeys(physicalObservation, ["observation_sha256", "phase", "purpose", "raw_values", "schema_version", "targets"], code)
        semanticSection = "CONTROLLER_PHASE_\(phase)_OBSERVATION_SCHEMA"
        guard try integer(physicalObservation["schema_version"], code) == 1,
              try string(physicalObservation["purpose"], code) == "CI3_MAC_PHASE_EFFECT_OBSERVATION_V1",
              try string(physicalObservation["phase"], code) == phase,
              try bool(physicalObservation["raw_values"], code) == false else { try fail(code) }
        let observationHash = try string(physicalObservation["observation_sha256"], code)
        var observationBody = physicalObservation
        observationBody.removeValue(forKey: "observation_sha256")
        semanticSection = "CONTROLLER_PHASE_\(phase)_OBSERVATION_HASH"
        guard observationHash == (try sha256(compactJSONBytes(observationBody))) else { try fail(code) }
        semanticSection = "CONTROLLER_PHASE_\(phase)_TARGETS"
        let targets = try array(physicalObservation["targets"], code)
        let authorizedContract = phaseTargetContracts[phaseIndex]
        try exactKeys(authorizedContract, ["phase", "targets"], "TERMINAL_PHASE_TARGET")
        let authorizedTargets = try array(authorizedContract["targets"], code).map { try dictionary($0, "TERMINAL_PHASE_TARGET") }
        guard try string(authorizedContract["phase"], code) == phase,
              !targets.isEmpty, targets.count == authorizedTargets.count else { try fail("TERMINAL_PHASE_TARGET") }
        var targetRoles = Set<String>()
        for (targetIndex, rawTarget) in targets.enumerated() {
            let target = try dictionary(rawTarget, code)
            let authorized = authorizedTargets[targetIndex]
            try exactKeys(authorized, ["allowed_gids", "allowed_uids", "immutable", "modes", "path_sha256", "role", "state"], "TERMINAL_PHASE_TARGET")
            try exactKeys(target, ["identity_sha256", "metadata", "path", "path_sha256", "role", "sha256", "state"], "TERMINAL_PHASE_TARGET")
            let role = try string(target["role"], code)
            let state = try string(target["state"], code)
            let targetPath = try string(target["path"], code)
            guard !targetRoles.contains(role), ["PRESENT", "ABSENT"].contains(state),
                  targetPath.hasPrefix("/"), !targetPath.contains("/../"),
                  try string(target["path_sha256"], code) == sha256(Data(targetPath.utf8)),
                  try string(authorized["role"], code) == role,
                  try string(authorized["state"], code) == state,
                  try string(authorized["path_sha256"], code) == sha256(Data(targetPath.utf8)) else { try fail("TERMINAL_PHASE_TARGET") }
            targetRoles.insert(role)
            if state == "PRESENT" {
                let metadata = try dictionary(target["metadata"], code)
                try exactKeys(metadata, ["dev", "gid", "ino", "mode", "mtime_ns", "nlink", "size", "uid"], code)
                let physical = Physical(
                    uid: UInt32(try integer(metadata["uid"], code)), gid: UInt32(try integer(metadata["gid"], code)),
                    mode: UInt16(try integer(metadata["mode"], code)), nlink: UInt16(try integer(metadata["nlink"], code)),
                    size: Int64(try integer(metadata["size"], code)), mtimeNS: try string(metadata["mtime_ns"], code),
                    dev: try string(metadata["dev"], code), ino: try string(metadata["ino"], code), flags: 0
                )
                let (currentBytes, currentPhysical) = try readBoundFile(
                    targetPath, expected: metadata, mode: physical.mode, code: "TERMINAL_PHASE_TARGET"
                )
                guard try string(target["sha256"], code) == sha256(currentBytes),
                      try string(target["identity_sha256"], code) == physicalIdentityHash(physical),
                      try string(target["identity_sha256"], code) == physicalIdentityHash(currentPhysical),
                      physical.nlink == 1,
                      (try array(authorized["modes"], code).compactMap { $0 as? Int }).contains(Int(physical.mode)),
                      (try array(authorized["allowed_uids"], code).compactMap { $0 as? Int }).contains(Int(physical.uid)),
                      (try array(authorized["allowed_gids"], code).compactMap { $0 as? Int }).contains(Int(physical.gid)),
                      !(try bool(authorized["immutable"], code)) || (currentPhysical.flags & UInt32(UF_IMMUTABLE)) != 0 else { try fail("TERMINAL_PHASE_TARGET") }
            } else {
                guard (try array(authorized["modes"], code)).isEmpty else { try fail("TERMINAL_PHASE_TARGET") }
                guard target["sha256"] is NSNull, target["identity_sha256"] is NSNull, target["metadata"] is NSNull else { try fail(code) }
                var absent = stat()
                let result = targetPath.withCString { Darwin.lstat($0, &absent) }
                guard result != 0, errno == ENOENT else { try fail("TERMINAL_PHASE_TARGET") }
            }
        }
        semanticSection = "CONTROLLER_PHASE_\(phase)_RESULT"
        guard try integer(receipt["schema_version"], code) == 1,
              try string(receipt["purpose"], code) == "CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1",
              try string(receipt["phase"], code) == phase,
              try string(receipt["claim_sha256"], code) == string(claimEntry["sha256"], code),
              try string(receipt["result_sha256"], code) == sha256(try compactJSONBytes(try dictionary(receipt["result"], code))),
              try bool(receipt["raw_values"], code) == false else { try fail(code) }
        let (_, _, result) = try evidenceObject(evidence, role: "\(prefix)-result", code)
        try exactKeys(result, ["claim_sha256", "phase", "physical_observation_sha256", "purpose", "raw_values", "receipt_sha256", "schema_version", "terminal_state"], code)
        guard try integer(result["schema_version"], code) == 1,
              try string(result["purpose"], code) == "CI3_MAC_PHASE_RESULT_V1",
              try string(result["phase"], code) == phase,
              try string(result["claim_sha256"], code) == string(claimEntry["sha256"], code),
              try string(result["receipt_sha256"], code) == string(receiptEntry["sha256"], code),
              try string(result["physical_observation_sha256"], code) == observationHash,
              try string(result["terminal_state"], code) == "PHASE_SETTLED",
              try bool(result["raw_values"], code) == false else { try fail(code) }
        controllerPredecessor = try string(evidence.first(where: { ($0["role"] as? String) == "\(prefix)-result" })!["sha256"], code)
    }

    semanticSection = "TERMINAL_SETTLEMENT"
    let settlementContracts = try array(manifest["terminal_settlement_contracts"], code)
    guard settlementContracts.count == terminalSettlementPhases.count else { try fail(code) }
    let runScansResultRole = "\(evidencePrefix("controller", "RUN_SCANS"))-result"
    guard let runScansResultEntry = evidence.first(where: { ($0["role"] as? String) == runScansResultRole }) else { try fail(code) }
    var settlementPredecessor = try string(runScansResultEntry["sha256"], code)
    for (index, phase) in terminalSettlementPhases.enumerated() {
        let contract = try dictionary(settlementContracts[index], code)
        try exactKeys(contract, [
            "authority_sha", "controller_generation_id", "effect_authorized", "phase",
            "predecessor_contract_sha256", "purpose", "raw_values", "schema_version", "terminal_generation_id",
        ], code)
        guard try integer(contract["schema_version"], code) == 1,
              try string(contract["purpose"], code) == "CI3_TERMINAL_SETTLEMENT_CONTRACT_V1",
              try string(contract["phase"], code) == phase,
              try string(contract["authority_sha"], code) == authority,
              try string(contract["controller_generation_id"], code) == string(generations["controller"], code),
              try string(contract["terminal_generation_id"], code) == string(generations["terminal"], code),
              try string(contract["predecessor_contract_sha256"], code) == settlementPredecessor,
              try string(contract["effect_authorized"], code) == (phase == "INVOKE_WRITER" ? "PRIVILEGED_WRITER_ON_FROZEN_MANIFEST" : "REOPEN_ROOT_ANCHOR"),
              try bool(contract["raw_values"], code) == false else { try fail(code) }
        settlementPredecessor = try sha256(compactJSONBytes(contract))
    }
    let (terminalEntry, _, terminalReceipt) = try evidenceObject(evidence, role: "terminal-receipt", code)
    try exactKeys(terminalReceipt, [
        "authority_sha", "controller_generation_id", "finished_at", "normal_executor_authorized",
        "privileged_authority_path_sha256", "purpose", "raw_values", "run_scans_result_sha256",
        "scan_receipt_sha256", "schema_version", "terminal_generation_id",
        "terminal_settlement_contracts_sha256", "writer_binary_sha256", "writer_signature_sha256", "writer_source_sha256",
    ], code)
    let terminalScanRoots = try array(terminalReceipt["scan_receipt_sha256"], code)
    let observedScanRoots = try scans.map { entry -> [String: Any] in
        ["id": try string(entry["id"], code), "sha256": try string(entry["sha256"], code)]
    }
    guard try integer(terminalReceipt["schema_version"], code) == 1,
          try string(terminalReceipt["purpose"], code) == "CI3_TERMINAL_PREPARATION_RECEIPT_V1",
          try string(terminalReceipt["authority_sha"], code) == authority,
          try string(terminalReceipt["controller_generation_id"], code) == string(generations["controller"], code),
          try string(terminalReceipt["terminal_generation_id"], code) == string(generations["terminal"], code),
          try compactJSONArrayBytes(terminalScanRoots.map { try dictionary($0, code) }) == compactJSONArrayBytes(observedScanRoots),
          try string(terminalReceipt["run_scans_result_sha256"], code) == string(runScansResultEntry["sha256"], code),
          try string(terminalReceipt["terminal_settlement_contracts_sha256"], code) == sha256(compactJSONArrayBytes(settlementContracts.map { try dictionary($0, code) })),
          try string(terminalReceipt["writer_source_sha256"], code) == string(manifest["writer_source_sha256"], code),
          try string(terminalReceipt["writer_binary_sha256"], code) == string(manifest["writer_binary_sha256"], code),
          try string(terminalReceipt["writer_signature_sha256"], code) == string(manifest["writer_signature_sha256"], code),
          try string(terminalReceipt["privileged_authority_path_sha256"], code) == string(manifest["writer_authority_path_sha256"], code),
          try bool(terminalReceipt["normal_executor_authorized"], code) == false,
          isUTCTimestamp(try string(terminalReceipt["finished_at"], code)),
          try bool(terminalReceipt["raw_values"], code) == false,
          isHex(try string(terminalEntry["sha256"], code), count: 64) else { try fail(code) }

    semanticSection = "SCANS"
    for scanEntry in scans {
        let (_, _, scanReceipt) = try evidenceObject([[
            "role": try string(scanEntry["id"], code), "path": scanEntry["path"]!,
            "sha256": scanEntry["sha256"]!, "metadata": scanEntry["metadata"]!,
        ]], role: try string(scanEntry["id"], code), code)
        let scanID = try string(scanEntry["id"], code)
        guard let contract = scanContractsByID[scanID] else { try fail(code) }
        let observations = try array(scanReceipt["input_observations"], code)
        guard observations.count == 1 else { try fail(code) }
        let observation = try dictionary(observations[0], code)
        let (surfaceBytes, _) = try readBoundFile(
            try string(observation["path"], code), expected: try dictionary(observation["metadata"], code), code: code
        )
        let surface = try jsonObject(surfaceBytes, code)
        semanticSection = "SCAN_SURFACE_FIELDS"
        try exactKeys(surface, [
            "authority_sha", "collector_version", "content_base64", "content_byte_length", "content_sha256",
            "controller_generation_id", "purpose", "raw_values", "scan_id", "schema_version",
            "source_observation", "source_role", "source_roots", "terminal_generation_id",
        ], code)
        guard try integer(surface["schema_version"], code) == 1,
              try string(surface["purpose"], code) == "CI3_FINAL_OPERATION_SCAN_SURFACE_V1",
              try string(surface["scan_id"], code) == scanID,
              try string(surface["collector_version"], code) == string(contract["collector_version"], code),
              try string(surface["source_role"], code) == string(contract["source_role"], code),
              try string(surface["authority_sha"], code) == authority,
              try string(surface["controller_generation_id"], code) == string(generations["controller"], code),
              try string(surface["terminal_generation_id"], code) == string(generations["terminal"], code),
              !(try array(surface["source_roots"], code)).isEmpty,
              try bool(surface["raw_values"], code) == false,
              try string(scanReceipt["input_manifest_sha256"], code) == string(inputEntry["sha256"], code),
              try string(scanReceipt["tool_sha256"], code) == string(contract["tool_sha256"], code),
              try string(scanReceipt["scanner_schema_sha256"], code) == string(contract["contract_sha256"], code) else { try fail(code) }
        semanticSection = "SCAN_CONTENT_\(scanID.uppercased().replacingOccurrences(of: "-", with: "_"))"
        guard let encodedContent = surface["content_base64"] as? String,
              let content = Data(base64Encoded: encodedContent),
              content.base64EncodedString() == encodedContent,
              try integer(surface["content_byte_length"], code) == content.count,
              try string(surface["content_sha256"], code) == sha256(content),
              try containsSensitiveSemanticSurface(content, scanID: scanID) == false else { try fail(code) }
        semanticSection = "SCAN_SOURCE_ROOT_\(scanID.uppercased().replacingOccurrences(of: "-", with: "_"))"
        let sourceRoots = try array(surface["source_roots"], code)
        guard sourceRoots.count == 1 else { try fail(code) }
        let sourceRoot = try dictionary(sourceRoots[0], code)
        try exactKeys(sourceRoot, ["identity_sha256", "role", "sha256"], code)
        let sourceObservation = try dictionary(surface["source_observation"], code)
        try exactKeys(sourceObservation, [
            "absence_observation_sha256", "byte_range", "content_sha256", "identity_sha256", "metadata",
            "parent_identity_sha256", "path", "path_sha256", "purpose", "raw_values", "scan_id",
            "schema_version", "source_semantics", "state",
        ], code)
        let sourcePath = try string(sourceObservation["path"], code)
        let expectedSuffix = "/final-sources/\(scanID).surface"
        guard sourcePath.hasPrefix("/"), sourcePath.hasSuffix(expectedSuffix), !sourcePath.contains("/../"),
              try integer(sourceObservation["schema_version"], code) == 1,
              try string(sourceObservation["purpose"], code) == "CI3_TERMINAL_SCAN_SOURCE_OBSERVATION_V1",
              try string(sourceObservation["scan_id"], code) == scanID,
              try string(sourceObservation["source_semantics"], code) == scanID,
              try string(sourceObservation["path_sha256"], code) == sha256(Data(sourcePath.utf8)),
              try string(sourceRoot["role"], code) == string(contract["source_role"], code),
              try bool(sourceObservation["raw_values"], code) == false else { try fail(code) }
        let parentPath = (sourcePath as NSString).deletingLastPathComponent
        let parentPhysical = physical(try lstatValue(parentPath, code))
        guard parentPhysical.mode == 0o700,
              try string(sourceObservation["parent_identity_sha256"], code) == physicalIdentityHash(parentPhysical) else { try fail(code) }
        let sourceState = try string(sourceObservation["state"], code)
        if sourceState == "PRESENT" {
            let sourceMetadata = try dictionary(sourceObservation["metadata"], code)
            let (sourceBytes, sourcePhysical) = try readBoundFile(sourcePath, expected: sourceMetadata, code: code)
            let byteRange = try dictionary(sourceObservation["byte_range"], code)
            try exactKeys(byteRange, ["end", "start"], code)
            guard try integer(byteRange["start"], code) == 0,
                  try integer(byteRange["end"], code) == sourceBytes.count,
                  sourceBytes == content,
                  try string(sourceObservation["content_sha256"], code) == sha256(sourceBytes),
                  try string(sourceObservation["identity_sha256"], code) == physicalIdentityHash(sourcePhysical),
                  try string(sourceRoot["sha256"], code) == sha256(sourceBytes),
                  try string(sourceRoot["identity_sha256"], code) == physicalIdentityHash(sourcePhysical),
                  sourceObservation["absence_observation_sha256"] is NSNull else { try fail(code) }
        } else if sourceState == "ABSENT", scanID == "xcresult" {
            var absent = stat()
            let absentResult = sourcePath.withCString { Darwin.lstat($0, &absent) }
            guard absentResult != 0, errno == ENOENT, content.isEmpty,
                  sourceObservation["content_sha256"] is NSNull,
                  sourceObservation["identity_sha256"] is NSNull,
                  sourceObservation["metadata"] is NSNull,
                  sourceObservation["byte_range"] is NSNull,
                  try string(sourceRoot["sha256"], code) == sha256(Data()),
                  try string(sourceRoot["identity_sha256"], code) == string(sourceObservation["absence_observation_sha256"], code) else { try fail(code) }
            var absenceBody = sourceObservation
            absenceBody.removeValue(forKey: "absence_observation_sha256")
            guard try string(sourceObservation["absence_observation_sha256"], code) == sha256(compactJSONBytes(absenceBody)) else { try fail(code) }
        } else { try fail(code) }
        semanticSection = "SCAN_COMMAND_OUTPUT"
        let command: [String: Any] = [
            "scan_id": scanID, "collector_version": try string(contract["collector_version"], code),
            "contract_sha256": try string(contract["contract_sha256"], code),
            "source_role": try string(contract["source_role"], code),
            "tool_sha256": try string(contract["tool_sha256"], code),
        ]
        guard try string(scanReceipt["command_sha256"], code) == sha256(try compactJSONBytes(command)),
              try string(scanReceipt["output_sha256"], code) == sha256(compactJSONArrayBytes([[
                "byte_length": content.count, "sha256": try sha256(content),
              ]])) else { try fail(code) }
        guard try string(scanReceipt["local_bundle_sha256"], code) == string(manifest["local_bundle_sha256"], code),
              try string(scanReceipt["simulator_install_sha256"], code) == string(manifest["simulator_install_sha256"], code) else { try fail(code) }
    }
    semanticSection = "SCANS"
}

private func expectedAnchorRelativePath(authority: String, terminalGeneration: String) -> String {
    "\(authority)/\(terminalGeneration)/pre-anchor.json"
}

private func validateManifest(_ manifest: [String: Any], authority: String, generations arguments: [String], binaryHash: String, signatureHash: String) throws -> ([String: Any], [[String: Any]], [[String: Any]], Data) {
    let code = "TERMINAL_MANIFEST"
    try exactKeys(manifest, [
        "anchor_relative_path", "authority_manifest_sha256", "authority_sha", "authority_tree",
        "bootstrap_claim_sha256", "claim_result_chain_sha256", "components", "created_at_utc",
        "evidence", "generations", "important_finding_ids", "local_bundle_sha256",
        "privilege_mode", "purpose", "raw_values", "scan_receipts", "schema_version",
        "secret_read", "simulator_gate_sha256", "simulator_install_sha256",
        "ssh_provenance_sha256", "terminal_settlement_contracts", "terminal_state", "remote_bundle_sha256",
        "writer_authority_path_sha256", "writer_binary_sha256", "writer_signature_sha256", "writer_source_sha256",
    ], code)
    guard try integer(manifest["schema_version"], code) == 1,
          try string(manifest["purpose"], code) == "CI3_TERMINAL_ANCHOR_MANIFEST_V1",
          try string(manifest["authority_sha"], code) == authority,
          isHex(authority, count: 40),
          isHex(try string(manifest["authority_tree"], code), count: 40),
          isHex(try string(manifest["authority_manifest_sha256"], code), count: 64),
          isHex(try string(manifest["writer_source_sha256"], code), count: 64),
          isHex(try string(manifest["writer_binary_sha256"], code), count: 64),
          isHex(try string(manifest["writer_signature_sha256"], code), count: 64),
          try string(manifest["writer_signature_sha256"], code) == signatureHash,
          isHex(try string(manifest["bootstrap_claim_sha256"], code), count: 64),
          isHex(try string(manifest["claim_result_chain_sha256"], code), count: 64),
          isHex(try string(manifest["remote_bundle_sha256"], code), count: 64),
          isHex(try string(manifest["local_bundle_sha256"], code), count: 64),
          isHex(try string(manifest["ssh_provenance_sha256"], code), count: 64),
          isHex(try string(manifest["simulator_gate_sha256"], code), count: 64),
          isHex(try string(manifest["simulator_install_sha256"], code), count: 64),
          isHex(try string(manifest["writer_authority_path_sha256"], code), count: 64),
          try string(manifest["writer_binary_sha256"], code) == binaryHash,
          try string(manifest["terminal_state"], code) == "PRE_ANCHOR_PENDING_SETTLEMENT",
          try string(manifest["privilege_mode"], code) == "MACOS_ROOT_SINGLE_ADMIN_PROMPT",
          try bool(manifest["raw_values"], code) == false,
          try bool(manifest["secret_read"], code) == false,
          isUTCTimestamp(try string(manifest["created_at_utc"], code)) else { try fail(code) }
    let components = try dictionary(manifest["components"], code)
    try exactKeys(components, componentNames, code)
    for name in componentNames { try validateComponent(try dictionary(components[name], code), name: name, code) }
    let generations = try dictionary(manifest["generations"], code)
    try validateGenerationArguments(generations, arguments, code)
    let terminal = try string(generations["terminal"], code)
    guard try string(manifest["anchor_relative_path"], code) == expectedAnchorRelativePath(authority: authority, terminalGeneration: terminal) else { try fail(code) }
    let findings = try array(manifest["important_finding_ids"], code).compactMap { $0 as? String }
    guard findings == findingIDs else { try fail(code) }
    let evidence = try validateEvidence(try array(manifest["evidence"], code), code)
    guard let writerSource = evidence.first(where: { ($0["role"] as? String) == "writer-source" }),
          try string(writerSource["sha256"], code) == string(manifest["writer_source_sha256"], code),
          try string(dictionary(components["writer"], code)["sha256"], code) == string(manifest["writer_source_sha256"], code) else { try fail(code) }
    let scans = try validateScanReceipts(try array(manifest["scan_receipts"], code), authority: authority, generations: generations, code)
    try validateSemanticRoots(
        manifest: manifest, authority: authority, generations: generations,
        components: components, evidence: evidence, scans: scans, "TERMINAL_SEMANTICS"
    )
    return (generations, evidence, scans, try validatedJournalFrame(evidence, code))
}

private func anchorRoot() throws -> String {
#if CI3_SYNTHETIC_TEST
    guard let root = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_ANCHOR_ROOT"], root.hasPrefix("/"), !root.contains("/../") else {
        try fail("TEST_ROOT")
    }
    return root
#else
    guard getuid() == 0, geteuid() == 0 else { try fail("PRIVILEGE_REQUIRED") }
    return "/Library/Application Support/Agentempp/ci3-terminal-authority"
#endif
}

private func ensureDirectory(_ path: String, mode: mode_t) throws {
    var observed = stat()
    if path.withCString({ Darwin.lstat($0, &observed) }) == 0 {
        let observedMode = observed.st_mode & 0o777
        guard (observed.st_mode & S_IFMT) == S_IFDIR,
              observedMode == 0o700 || observedMode == 0o555 else { try fail("ANCHOR_PARENT") }
#if CI3_SYNTHETIC_TEST
        guard observed.st_uid == getuid(), observed.st_gid == getgid() else { try fail("ANCHOR_PARENT") }
#else
        guard observed.st_uid == 0, observed.st_gid == 0 else { try fail("ANCHOR_PARENT") }
#endif
        return
    }
    guard errno == ENOENT, path.withCString({ Darwin.mkdir($0, mode) }) == 0 else { try fail("ANCHOR_PARENT") }
    guard Darwin.chmod(path, mode) == 0 else { try fail("ANCHOR_PARENT") }
#if !CI3_SYNTHETIC_TEST
    guard Darwin.chown(path, 0, 0) == 0 else { try fail("ANCHOR_PARENT") }
#endif
}

private func secureAnchorDirectories(root: String, authority: String, terminalGeneration: String) throws -> String {
    let rootStat = try lstatValue(root, "ANCHOR_PARENT")
    guard (rootStat.st_mode & S_IFMT) == S_IFDIR else { try fail("ANCHOR_PARENT") }
#if !CI3_SYNTHETIC_TEST
    guard rootStat.st_uid == 0, rootStat.st_gid == 0,
          (rootStat.st_mode & 0o777) == 0o555 else { try fail("ANCHOR_PARENT") }
#else
    guard rootStat.st_uid == getuid(), rootStat.st_gid == getgid(),
          (rootStat.st_mode & 0o777) == 0o700 else { try fail("ANCHOR_PARENT") }
#endif
    let authorityDirectory = (root as NSString).appendingPathComponent(authority)
    // The authority directory must remain writable only while its single
    // version child is created. It is frozen before publication.
    try ensureDirectory(authorityDirectory, mode: 0o700)
    let generationDirectory = (authorityDirectory as NSString).appendingPathComponent(terminalGeneration)
    try ensureDirectory(generationDirectory, mode: 0o700)
    guard Darwin.chmod(authorityDirectory, 0o555) == 0 else { try fail("ANCHOR_PARENT") }
    return generationDirectory
}

private func validatePrivilegedClaim(_ claim: [String: Any], manifestHash: String, authority: String, terminalGeneration: String, sourceHash: String, binaryHash: String, anchorPath: String) throws {
    let code = "PRIVILEGED_CLAIM"
    try exactKeys(claim, [
        "anchor_path_sha256", "attempt", "authority_sha", "file_mode", "gid", "immutable_flag",
        "normal_executor_authorized", "purpose", "retry", "schema_version", "terminal_generation_id",
        "terminal_manifest_sha256", "uid", "writer_binary_sha256", "writer_source_sha256",
    ], code)
    guard try integer(claim["schema_version"], code) == 1,
          try string(claim["purpose"], code) == "CI3_PRIVILEGED_TERMINAL_ANCHOR_CLAIM_V1",
          try string(claim["authority_sha"], code) == authority,
          try string(claim["terminal_generation_id"], code) == terminalGeneration,
          try string(claim["terminal_manifest_sha256"], code) == manifestHash,
          try string(claim["writer_source_sha256"], code) == sourceHash,
          try string(claim["writer_binary_sha256"], code) == binaryHash,
          try string(claim["anchor_path_sha256"], code) == sha256(Data(anchorPath.utf8)),
          try integer(claim["attempt"], code) == 1, try bool(claim["retry"], code) == false,
          try integer(claim["uid"], code) == 0, try integer(claim["gid"], code) == 0,
          try string(claim["file_mode"], code) == "0444",
          try string(claim["immutable_flag"], code) == "UF_IMMUTABLE",
          try bool(claim["normal_executor_authorized"], code) == false else { try fail(code) }
}

private func validatePrivilegedAuthority(
    _ receipt: [String: Any],
    receiptPath: String,
    manifestPath: String,
    manifestHash: String,
    claimHash: String,
    anchorPath: String,
    authority: String,
    terminalGeneration: String,
    sourceHash: String,
    binaryHash: String,
    binaryIdentityHash: String,
    signatureHash: String
) throws {
    let code = "PRIVILEGED_AUTHORITY"
    try exactKeys(receipt, [
        "anchor_path_sha256", "attempt", "authority_path_sha256", "authority_sha",
        "normal_executor_authorized", "privileged_claim_sha256", "purpose", "raw_values",
        "retry", "schema_version", "terminal_generation_id", "terminal_manifest_path_sha256",
        "terminal_manifest_sha256", "writer_binary_sha256", "writer_executable_gid",
        "writer_executable_identity_sha256", "writer_executable_immutable_flag",
        "writer_executable_mode", "writer_executable_path_sha256", "writer_executable_uid",
        "writer_signature_sha256", "writer_source_sha256",
    ], code)
    guard try integer(receipt["schema_version"], code) == 1,
          try string(receipt["purpose"], code) == "CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1",
          try string(receipt["authority_sha"], code) == authority,
          try string(receipt["terminal_generation_id"], code) == terminalGeneration,
          try string(receipt["terminal_manifest_sha256"], code) == manifestHash,
          try string(receipt["terminal_manifest_path_sha256"], code) == sha256(Data(manifestPath.utf8)),
          try string(receipt["writer_source_sha256"], code) == sourceHash,
          try string(receipt["writer_binary_sha256"], code) == binaryHash,
          try string(receipt["writer_signature_sha256"], code) == signatureHash,
          try string(receipt["writer_executable_path_sha256"], code) == sha256(Data(CommandLine.arguments[0].utf8)),
          try string(receipt["writer_executable_identity_sha256"], code) == binaryIdentityHash,
          try string(receipt["privileged_claim_sha256"], code) == claimHash,
          try string(receipt["authority_path_sha256"], code) == sha256(Data(receiptPath.utf8)),
          try string(receipt["anchor_path_sha256"], code) == sha256(Data(anchorPath.utf8)),
          try integer(receipt["writer_executable_uid"], code) == 0,
          try integer(receipt["writer_executable_gid"], code) == 0,
          try string(receipt["writer_executable_mode"], code) == "0555",
          try string(receipt["writer_executable_immutable_flag"], code) == "UF_IMMUTABLE",
          try integer(receipt["attempt"], code) == 1,
          try bool(receipt["retry"], code) == false,
          try bool(receipt["normal_executor_authorized"], code) == false,
          try bool(receipt["raw_values"], code) == false else { try fail(code) }
}

private func immutableAnchorRequired() -> Bool {
#if CI3_SYNTHETIC_TEST
    return ProcessInfo.processInfo.environment["CI3_SYNTHETIC_REAL_IMMUTABLE"] == "1"
#else
    return true
#endif
}

private func syntheticWriteAnchorCrashHook(path: String, boundary: String) throws {
#if CI3_SYNTHETIC_TEST
    let selected = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_WRITE_ANCHOR_CRASH_AFTER"]
    if selected == "\((path as NSString).lastPathComponent):\(boundary)" { try fail("SYNTHETIC_CRASH") }
#endif
}

private func anchorPhysicalWithoutFlags(_ value: Physical) -> [String] {
    [
        String(value.uid), String(value.gid), String(value.mode), String(value.nlink),
        String(value.size), value.mtimeNS, value.dev, value.ino,
    ]
}

private func writeAnchor(
    _ bytes: Data, to anchorPath: String, originalPrivilegedClaimSha256: String
) throws -> String {
    guard isHex(originalPrivilegedClaimSha256, count: 64) else { try fail("PRIVILEGED_CLAIM") }
    let expectedHash = try sha256(bytes)
    let requireImmutable = immutableAnchorRequired()
    let parent = (anchorPath as NSString).deletingLastPathComponent
    let leaf = (anchorPath as NSString).lastPathComponent
    guard !leaf.isEmpty, leaf != ".", leaf != "..", !leaf.contains("/") else { try fail("ANCHOR_EXISTING") }
    let parentFD = Darwin.open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard parentFD >= 0 else { try fail("ANCHOR_FSYNC") }
    defer { Darwin.close(parentFD) }
    var existing = stat()
    if anchorPath.withCString({ Darwin.lstat($0, &existing) }) == 0 {
        let descriptor = Darwin.open(anchorPath, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { try fail("ANCHOR_EXISTING") }
        defer { Darwin.close(descriptor) }
        let before = try fstatValue(descriptor, "ANCHOR_EXISTING")
        let observed = physical(before)
        let expectedUID: uid_t
        let expectedGID: gid_t
#if CI3_SYNTHETIC_TEST
        expectedUID = geteuid(); expectedGID = getegid()
#else
        expectedUID = 0; expectedGID = 0
#endif
        guard (before.st_mode & S_IFMT) == S_IFREG, observed.uid == expectedUID,
              observed.gid == expectedGID, observed.mode == 0o444, observed.nlink == 1 else {
            try fail("ANCHOR_EXISTING")
        }
        let existingBytes = try readDescriptorBytes(descriptor, "ANCHOR_EXISTING")
        let afterRead = physical(try fstatValue(descriptor, "ANCHOR_EXISTING"))
        var relative = stat()
        guard existingBytes == bytes, try sha256(existingBytes) == expectedHash,
              observed == afterRead,
              leaf.withCString({ Darwin.fstatat(parentFD, $0, &relative, AT_SYMLINK_NOFOLLOW) }) == 0,
              physical(relative) == afterRead else { try fail("ANCHOR_EXISTING") }
        if requireImmutable && (afterRead.flags & UInt32(UF_IMMUTABLE)) == 0 {
            // The validated privileged claim is the sole recovery authority for
            // adopting the exact O_EXCL-created 0444 prefix.  A pathname or
            // byte match without that claim never reaches this function.
            try syntheticWriteAnchorCrashHook(path: anchorPath, boundary: "BEFORE_FLAGS")
            guard Darwin.fchflags(descriptor, UInt32(UF_IMMUTABLE)) == 0,
                  Darwin.fsync(descriptor) == 0, Darwin.fsync(parentFD) == 0 else {
                try fail("ANCHOR_IMMUTABLE")
            }
            try syntheticWriteAnchorCrashHook(path: anchorPath, boundary: "AFTER_FLAGS")
        }
        let final = physical(try fstatValue(descriptor, "ANCHOR_IMMUTABLE"))
        guard anchorPhysicalWithoutFlags(final) == anchorPhysicalWithoutFlags(afterRead),
              !requireImmutable || (final.flags & UInt32(UF_IMMUTABLE)) != 0,
              leaf.withCString({ Darwin.fstatat(parentFD, $0, &relative, AT_SYMLINK_NOFOLLOW) }) == 0,
              physical(relative) == final,
              try readDescriptorBytes(descriptor, "ANCHOR_READBACK") == bytes else {
            try fail("ANCHOR_READBACK")
        }
        return "EXISTS_VERIFIED"
    }
    guard errno == ENOENT else { try fail("ANCHOR_EXISTING") }
    let descriptor = Darwin.open(anchorPath, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o444)
    guard descriptor >= 0 else { try fail("ANCHOR_CREATE") }
    var completed = false
    defer {
        Darwin.close(descriptor)
        if !completed { /* evidence remains by design */ }
    }
    let writeResult = bytes.withUnsafeBytes { rawBuffer -> Bool in
        guard let base = rawBuffer.baseAddress else { return bytes.isEmpty }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
            if count <= 0 { return false }
            offset += count
        }
        return true
    }
    guard writeResult, Darwin.fchmod(descriptor, 0o444) == 0 else { try fail("ANCHOR_CREATE") }
#if !CI3_SYNTHETIC_TEST
    guard Darwin.fchown(descriptor, 0, 0) == 0 else { try fail("ANCHOR_CREATE") }
#endif
    guard Darwin.fsync(descriptor) == 0 else { try fail("ANCHOR_CREATE") }
    completed = true
    guard Darwin.fsync(parentFD) == 0 else { try fail("ANCHOR_FSYNC") }
    let beforeFlags = physical(try fstatValue(descriptor, "ANCHOR_CREATE"))
    try syntheticWriteAnchorCrashHook(path: anchorPath, boundary: "BEFORE_FLAGS")
    if requireImmutable {
        guard Darwin.fchflags(descriptor, UInt32(UF_IMMUTABLE)) == 0 else { try fail("ANCHOR_IMMUTABLE") }
    }
    guard Darwin.fsync(descriptor) == 0, Darwin.fsync(parentFD) == 0 else { try fail("ANCHOR_FSYNC") }
    try syntheticWriteAnchorCrashHook(path: anchorPath, boundary: "AFTER_FLAGS")
    let final = physical(try fstatValue(descriptor, "ANCHOR_IMMUTABLE"))
    var relative = stat()
    let readback = try readDescriptorBytes(descriptor, "ANCHOR_READBACK")
    guard anchorPhysicalWithoutFlags(final) == anchorPhysicalWithoutFlags(beforeFlags),
          !requireImmutable || (final.flags & UInt32(UF_IMMUTABLE)) != 0,
          leaf.withCString({ Darwin.fstatat(parentFD, $0, &relative, AT_SYMLINK_NOFOLLOW) }) == 0,
          physical(relative) == final, readback == bytes, try sha256(readback) == expectedHash else {
        try fail("ANCHOR_READBACK")
    }
    return "CREATED"
}

private func metadataDictionary(_ value: Physical) -> [String: Any] {
    [
        "uid": Int(value.uid), "gid": Int(value.gid), "mode": Int(value.mode),
        "nlink": Int(value.nlink), "size": Int(value.size), "mtime_ns": value.mtimeNS,
        "dev": value.dev, "ino": value.ino,
    ]
}

private func phaseObservation(phase: String, targets: [[String: Any]]) throws -> [String: Any] {
    var body: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_MAC_PHASE_EFFECT_OBSERVATION_V1",
        "phase": phase, "targets": targets, "raw_values": false,
    ]
    body["observation_sha256"] = try sha256(compactJSONBytes(body))
    return body
}

private func presentPhaseTarget(role: String, path: String, code: String) throws -> [String: Any] {
    let observedStat = try lstatValue(path, code)
    let observed = physical(observedStat)
    let (bytes, readback) = try readBoundFile(path, mode: observed.mode, code: code)
    guard observed.nlink == 1, try physicalIdentityHash(observed) == physicalIdentityHash(readback) else { try fail(code) }
    return [
        "role": role, "state": "PRESENT", "path": path,
        "path_sha256": try sha256(Data(path.utf8)), "sha256": try sha256(bytes),
        "identity_sha256": try physicalIdentityHash(observed), "metadata": metadataDictionary(observed),
    ]
}

private func writeTerminalPhaseArtifact(
    _ bytes: Data, path: String, originalPrivilegedClaimSha256: String
) throws -> String {
    do {
        return try writeAnchor(
            bytes, to: path, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        )
    } catch let failure as WriterFailure where failure.code == "SYNTHETIC_CRASH" {
        throw failure
    } catch {
        try fail("TERMINAL_SETTLEMENT")
    }
}

// The operational binary has no crash-injection surface.  The synthetic test
// build records its one-shot interruption inside the privileged phase
// directory, before the terminal commit marker exists.  A restart must reopen
// the byte-identical marker and continue the same transaction; it can never
// manufacture a second effect or append normal-executor state after PASS.
private func syntheticTerminalCrashHook(
    phase: String, boundary: String, phaseDirectory: String, originalPrivilegedClaimSha256: String
) throws {
#if CI3_SYNTHETIC_TEST
    let environment = ProcessInfo.processInfo.environment
    guard let scenario = environment["CI3_SYNTHETIC_E2E_SCENARIO"],
          let scenarioHash = environment["CI3_SYNTHETIC_SCENARIO_SHA256"] else { return }
    let expected = "\(phase):\(boundary)"
    guard scenario == expected else { return }
    guard try sha256(Data(scenario.utf8)) == scenarioHash else { try fail("SELF_TEST_SCENARIO") }
    let marker: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_SYNTHETIC_PRIVILEGED_CRASH_MARKER_V1",
        "phase": phase, "boundary": boundary, "scenario_sha256": scenarioHash,
        "effect_reexecution_allowed": false, "raw_values": false,
    ]
    let markerBytes = try compactJSONBytes(marker)
    let prefix = phase.lowercased().replacingOccurrences(of: "_", with: "-")
    let path = (phaseDirectory as NSString).appendingPathComponent("\(prefix).\(boundary).synthetic-crash.json")
    if try writeTerminalPhaseArtifact(
        markerBytes, path: path, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
    ) == "CREATED" {
        try fail("SYNTHETIC_CRASH")
    }
#endif
}

private func syntheticTerminalArtifactCrashHook(_ boundary: String) throws {
#if CI3_SYNTHETIC_TEST
    guard let selected = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_TERMINAL_CRASH_AFTER"] else {
        return
    }
    let allowed = ["COMPLETE_FINAL_SCAN", "FINAL_FRAMES", "MARKER_READBACK", "DIRECTORY_FREEZE"]
    guard allowed.contains(selected) else { try fail("SELF_TEST_SCENARIO") }
    if selected == boundary { try fail("SYNTHETIC_CRASH") }
#endif
}

private func publishTerminalTransaction(
    generationDirectory: String, preAnchorPath: String, preAnchorBytes: Data,
    authorityReceiptBytes: Data, authority: String, generations: [String: Any],
    components: [String: Any], settlementContracts: [[String: Any]], semanticEvidenceBytes: Data,
    controllerJournalFrameBytes: Data, originalPrivilegedClaimSha256: String
) throws -> (String, String) {
    let code = "TERMINAL_SETTLEMENT"
    guard settlementContracts.count == 2 else { try fail(code) }
    let phaseDirectory = (generationDirectory as NSString).appendingPathComponent("terminal-phases")
    try ensureDirectory(phaseDirectory, mode: 0o700)
    let controllerGeneration = try string(generations["controller"], code)
    let terminalGeneration = try string(generations["terminal"], code)
    var predecessor = try string(settlementContracts[0]["predecessor_contract_sha256"], code)
    var phaseRoots: [[String: Any]] = []
    var phaseObjects: [String: [[String: Any]]] = [:]
    var aggregateStatus = "EXISTS_VERIFIED"
    for (index, phase) in terminalSettlementPhases.enumerated() {
        let settlementContract = settlementContracts[index]
        guard try string(settlementContract["phase"], code) == phase,
              try string(settlementContract["authority_sha"], code) == authority,
              try string(settlementContract["controller_generation_id"], code) == controllerGeneration,
              try string(settlementContract["terminal_generation_id"], code) == terminalGeneration else { try fail(code) }
        try syntheticTerminalCrashHook(
            phase: phase, boundary: "before-claim", phaseDirectory: phaseDirectory,
            originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        )
        let claim: [String: Any] = [
            "schema_version": 1, "purpose": "CI3_MAC_PHASE_CLAIM_V1", "phase": phase,
            "authority_sha": authority, "controller_generation_id": controllerGeneration,
            "predecessor_result_sha256": predecessor,
            "contract_sha256": try sha256(compactJSONBytes(settlementContract)),
            "attempt": 1, "retry": false, "raw_values": false,
        ]
        let claimBytes = try compactJSONBytes(claim)
        let claimHash = try sha256(claimBytes)
        let prefix = phase.lowercased().replacingOccurrences(of: "_", with: "-")
        let claimPath = (phaseDirectory as NSString).appendingPathComponent("\(prefix).claim.json")
        if try writeTerminalPhaseArtifact(
            claimBytes, path: claimPath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        ) == "CREATED" { aggregateStatus = "CREATED" }
        try syntheticTerminalCrashHook(
            phase: phase, boundary: "after-claim", phaseDirectory: phaseDirectory,
            originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        )
        let targets: [[String: Any]]
        let effectResult: [String: Any]
        if phase == "INVOKE_WRITER" {
            targets = [try presentPhaseTarget(role: "terminal-pre-anchor", path: preAnchorPath, code: code)]
            effectResult = [
                "pre_anchor_sha256": try sha256(preAnchorBytes),
                "writer_transaction": "SINGLE_PRIVILEGED_INVOCATION", "raw_values": false,
            ]
        } else {
            let invokeResultPath = (phaseDirectory as NSString).appendingPathComponent("invoke-writer.result.json")
            targets = [
                try presentPhaseTarget(role: "terminal-pre-anchor-readback", path: preAnchorPath, code: code),
                try presentPhaseTarget(role: "invoke-writer-result-root", path: invokeResultPath, code: code),
            ]
            effectResult = [
                "pre_anchor_sha256": try sha256(preAnchorBytes),
                "readback_verified": true, "raw_values": false,
            ]
        }
        let observation = try phaseObservation(phase: phase, targets: targets)
        try syntheticTerminalCrashHook(
            phase: phase, boundary: "after-effect", phaseDirectory: phaseDirectory,
            originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        )
        let receipt: [String: Any] = [
            "schema_version": 1, "purpose": "CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1", "phase": phase,
            "claim_sha256": claimHash, "result": effectResult,
            "result_sha256": try sha256(compactJSONBytes(effectResult)),
            "observation": observation, "raw_values": false,
        ]
        let receiptBytes = try compactJSONBytes(receipt)
        let receiptHash = try sha256(receiptBytes)
        let receiptPath = (phaseDirectory as NSString).appendingPathComponent("\(prefix).receipt.json")
        if try writeTerminalPhaseArtifact(
            receiptBytes, path: receiptPath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        ) == "CREATED" { aggregateStatus = "CREATED" }
        try syntheticTerminalCrashHook(
            phase: phase, boundary: "after-receipt", phaseDirectory: phaseDirectory,
            originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        )
        let result: [String: Any] = [
            "schema_version": 1, "purpose": "CI3_MAC_PHASE_RESULT_V1", "phase": phase,
            "claim_sha256": claimHash, "receipt_sha256": receiptHash,
            "physical_observation_sha256": try string(observation["observation_sha256"], code),
            "terminal_state": "PHASE_SETTLED", "raw_values": false,
        ]
        let resultBytes = try compactJSONBytes(result)
        let resultHash = try sha256(resultBytes)
        let resultPath = (phaseDirectory as NSString).appendingPathComponent("\(prefix).result.json")
        if try writeTerminalPhaseArtifact(
            resultBytes, path: resultPath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        ) == "CREATED" { aggregateStatus = "CREATED" }
        try syntheticTerminalCrashHook(
            phase: phase, boundary: "after-result", phaseDirectory: phaseDirectory,
            originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        )
        phaseRoots.append([
            "phase": phase, "claim_sha256": claimHash,
            "receipt_sha256": receiptHash, "result_sha256": resultHash,
        ])
        phaseObjects[phase] = [claim, receipt, result]
        predecessor = resultHash
        try syntheticTerminalCrashHook(
            phase: phase, boundary: "after-event", phaseDirectory: phaseDirectory,
            originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        )
    }
    guard phaseObjects.count == 2 else { try fail(code) }
    let contractsHash = try sha256(compactJSONArrayBytes(settlementContracts))
    let phaseGraphHash = try sha256(compactJSONArrayBytes(phaseRoots))
    let invokeRoot = phaseRoots[0]
    let verifyRoot = phaseRoots[1]
    let terminalBodyBeforeFinalScan: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_TERMINAL_SETTLEMENT_V1",
        "authority_sha": authority, "generations": generations,
        "terminal_generation_id": terminalGeneration,
        "pre_anchor_sha256": try sha256(preAnchorBytes),
        "invoke_writer": [
            "claim_sha256": try string(invokeRoot["claim_sha256"], code),
            "receipt_sha256": try string(invokeRoot["receipt_sha256"], code),
            "result_sha256": try string(invokeRoot["result_sha256"], code),
        ],
        "verify_anchor": [
            "claim_sha256": try string(verifyRoot["claim_sha256"], code),
            "receipt_sha256": try string(verifyRoot["receipt_sha256"], code),
            "result_sha256": try string(verifyRoot["result_sha256"], code),
        ],
        "settlement_authority_sha256": try sha256(authorityReceiptBytes),
        "terminal_settlement_contracts_sha256": contractsHash,
        "terminal_phase_graph_sha256": phaseGraphHash,
        "terminal_state": "TERMINAL_PASS", "append_only": true, "no_clobber": true, "raw_values": false,
    ]
    var terminalBytes = semanticEvidenceBytes + preAnchorBytes + (try compactJSONBytes(terminalBodyBeforeFinalScan))
    for phase in terminalSettlementPhases {
        for object in phaseObjects[phase]! { terminalBytes += try compactJSONBytes(object) }
    }
    var finalScanRoots: [[String: Any]] = []
    for scanID in scanIDs {
        guard try !containsSensitiveScanContent(terminalBytes, scanID: scanID) else { try fail("TERMINAL_FINAL_SCAN") }
        finalScanRoots.append([
            "id": scanID, "input_sha256": try sha256(terminalBytes),
            "input_byte_length": terminalBytes.count, "match_count": 0,
        ])
    }
    var body = terminalBodyBeforeFinalScan
    body["terminal_final_scan_sha256"] = try sha256(compactJSONArrayBytes(finalScanRoots))
    var settlement = body
    settlement["settlement_sha256"] = try sha256(compactJSONBytes(body))
    let settlementBytes = try compactJSONBytes(settlement)
    let settlementPath = (generationDirectory as NSString).appendingPathComponent("terminal-settlement.json")
    if try writeTerminalPhaseArtifact(
        settlementBytes, path: settlementPath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
    ) == "CREATED" { aggregateStatus = "CREATED" }
    let (settlementReadback, _) = try readBoundFile(settlementPath, mode: 0o444, code: code)
    guard settlementReadback == settlementBytes else { try fail(code) }
    let writerOutput: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_PRIVILEGED_WRITER_OUTPUT_V1",
        "authority_sha": authority, "terminal_generation_id": terminalGeneration,
        "pre_anchor_sha256": try sha256(preAnchorBytes),
        "terminal_settlement_sha256": try sha256(settlementBytes),
        "raw_values": false,
    ]
    let writerOutputBytes = try compactJSONBytes(writerOutput)
    let writerOutputPath = (generationDirectory as NSString).appendingPathComponent("writer-output.json")
    if try writeTerminalPhaseArtifact(
        writerOutputBytes, path: writerOutputPath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
    ) == "CREATED" { aggregateStatus = "CREATED" }
    let finalInput = terminalBytes + settlementBytes + writerOutputBytes
    var finalCounters: [[String: Any]] = []
    for scanID in scanIDs {
        guard try !containsSensitiveSemanticSurface(finalInput, scanID: scanID) else { try fail("TERMINAL_FINAL_SCAN") }
        finalCounters.append(["id": scanID, "match_count": 0])
    }
    let finalScan: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_TERMINAL_FINAL_SCAN_V1",
        "authority_sha": authority, "terminal_generation_id": terminalGeneration,
        "surface_roles": Array(terminalFinalSurfaceRoles.dropLast()), "scan_results": finalCounters,
        "input_sha256": try sha256(finalInput), "input_byte_length": finalInput.count,
        "raw_values": false,
    ]
    let finalScanBytes = try compactJSONBytes(finalScan)
    let finalScanPath = (generationDirectory as NSString).appendingPathComponent("terminal-final-scan.json")
    if try writeTerminalPhaseArtifact(
        finalScanBytes, path: finalScanPath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
    ) == "CREATED" { aggregateStatus = "CREATED" }
    let complete: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_TERMINAL_COMPLETE_RESULT_V1",
        "authority_sha": authority, "generations": generations,
        "terminal_generation_id": terminalGeneration,
        "pre_anchor_sha256": try sha256(preAnchorBytes),
        "terminal_settlement_sha256": try sha256(settlementBytes),
        "terminal_final_scan_sha256": try sha256(finalScanBytes),
        "terminal_state": "COMPLETE", "raw_values": false,
    ]
    let completeBytes = try compactJSONBytes(complete)
    guard try !containsSensitiveScanContent(completeBytes, scanID: "attachment") else { try fail("TERMINAL_FINAL_SCAN") }
    let completePath = (generationDirectory as NSString).appendingPathComponent("complete-result.json")
    if try writeTerminalPhaseArtifact(
        completeBytes, path: completePath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
    ) == "CREATED" { aggregateStatus = "CREATED" }
    var completeCounters: [[String: Any]] = []
    for scanID in scanIDs {
        guard try !containsSensitiveSemanticSurface(completeBytes, scanID: scanID) else { try fail("TERMINAL_FINAL_SCAN") }
        completeCounters.append(["id": scanID, "match_count": 0])
    }
    let completeFinalScan: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_TERMINAL_COMPLETE_FINAL_SCAN_V1",
        "authority_sha": authority, "terminal_generation_id": terminalGeneration,
        "surface_roles": ["complete-result"], "scan_results": completeCounters,
        "input_sha256": try sha256(completeBytes), "input_byte_length": completeBytes.count,
        "raw_values": false,
    ]
    let completeFinalScanBytes = try compactJSONBytes(completeFinalScan)
    let completeFinalScanPath = (generationDirectory as NSString).appendingPathComponent("complete-final-scan.json")
    if try writeTerminalPhaseArtifact(
        completeFinalScanBytes, path: completeFinalScanPath,
        originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
    ) == "CREATED" { aggregateStatus = "CREATED" }
    for (candidatePath, expectedBytes) in [
        (writerOutputPath, writerOutputBytes), (finalScanPath, finalScanBytes), (completePath, completeBytes),
        (completeFinalScanPath, completeFinalScanBytes),
    ] {
        let (readback, _) = try readBoundFile(candidatePath, mode: 0o444, code: code)
        guard readback == expectedBytes else { try fail(code) }
    }
    try syntheticTerminalArtifactCrashHook("COMPLETE_FINAL_SCAN")
    let stdoutBytes = Data("CONTROLLER RESUME TERMINAL_PASS state=TERMINAL_PASS raw_values=false\n".utf8)
    let stderrBytes = Data()
    let completeObjects = try parseJournalFrame(controllerJournalFrameBytes, code)
        .filter { $0.0 == "events/COMPLETE.json" }
    guard completeObjects.count == 1 else { try fail("TERMINAL_JOURNAL_FRAME") }
    let completeEventBytes = completeObjects[0].1
    let completeEvent = try jsonObject(completeEventBytes, "TERMINAL_JOURNAL_FRAME")
    try exactKeys(completeEvent, ["event", "result", "result_sha256", "state"], "TERMINAL_JOURNAL_FRAME")
    let completeResult = try dictionary(completeEvent["result"], "TERMINAL_JOURNAL_FRAME")
    try exactKeys(completeResult, ["terminal_commit_contract_sha256"], "TERMINAL_JOURNAL_FRAME")
    guard try string(completeEvent["event"], "TERMINAL_JOURNAL_FRAME") == "COMPLETE",
          try string(completeEvent["state"], "TERMINAL_JOURNAL_FRAME") == "COMPLETE",
          isHex(try string(completeResult["terminal_commit_contract_sha256"], "TERMINAL_JOURNAL_FRAME"), count: 64),
          try string(completeEvent["result_sha256"], "TERMINAL_JOURNAL_FRAME") == sha256(compactJSONBytes(completeResult)) else {
        try fail("TERMINAL_JOURNAL_FRAME")
    }
    let journalFrameBytes = controllerJournalFrameBytes
    for bytes in [stdoutBytes, stderrBytes, completeEventBytes, journalFrameBytes] {
        for scanID in scanIDs {
            guard try !containsSensitiveSemanticSurface(bytes, scanID: scanID) else { try fail("TERMINAL_FINAL_SCAN") }
        }
    }
    let journalFramePath = (generationDirectory as NSString).appendingPathComponent("controller-journal.final.frame")
    let stdoutFramePath = (generationDirectory as NSString).appendingPathComponent("controller-stdout.final.frame")
    let stderrFramePath = (generationDirectory as NSString).appendingPathComponent("controller-stderr.final.frame")
    let completeEventPath = (generationDirectory as NSString).appendingPathComponent("controller-complete.event.json")
    for (candidatePath, bytes) in [
        (journalFramePath, journalFrameBytes), (stdoutFramePath, stdoutBytes),
        (stderrFramePath, stderrBytes), (completeEventPath, completeEventBytes),
    ] {
        if try writeTerminalPhaseArtifact(
            bytes, path: candidatePath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
        ) == "CREATED" { aggregateStatus = "CREATED" }
        let (readback, _) = try readBoundFile(candidatePath, mode: 0o444, code: code)
        guard readback == bytes else { try fail(code) }
    }
    try syntheticTerminalArtifactCrashHook("FINAL_FRAMES")
    let markerPath = (generationDirectory as NSString).appendingPathComponent("terminal-pass.marker.json")
    let privilegedAuthorityPath = (generationDirectory as NSString).appendingPathComponent("privileged-authority.receipt.json")
    let invokeWriterClaimPath = (phaseDirectory as NSString).appendingPathComponent("invoke-writer.claim.json")
    let invokeWriterReceiptPath = (phaseDirectory as NSString).appendingPathComponent("invoke-writer.receipt.json")
    let invokeWriterResultPath = (phaseDirectory as NSString).appendingPathComponent("invoke-writer.result.json")
    let verifyAnchorClaimPath = (phaseDirectory as NSString).appendingPathComponent("verify-anchor.claim.json")
    let verifyAnchorReceiptPath = (phaseDirectory as NSString).appendingPathComponent("verify-anchor.receipt.json")
    let verifyAnchorResultPath = (phaseDirectory as NSString).appendingPathComponent("verify-anchor.result.json")
    let controllerComponent = try dictionary(components["controller"], code)
    let launcherComponent = try dictionary(components["launcher"], code)
    let markerPaths: [String: Any] = [
        "complete_event_sha256": try sha256(Data(completeEventPath.utf8)),
        "complete_final_scan_sha256": try sha256(Data(completeFinalScanPath.utf8)),
        "complete_result_sha256": try sha256(Data(completePath.utf8)),
        "journal_frame_sha256": try sha256(Data(journalFramePath.utf8)),
        "invoke_writer_claim_sha256": try sha256(Data(invokeWriterClaimPath.utf8)),
        "invoke_writer_receipt_sha256": try sha256(Data(invokeWriterReceiptPath.utf8)),
        "invoke_writer_result_sha256": try sha256(Data(invokeWriterResultPath.utf8)),
        "marker_sha256": try sha256(Data(markerPath.utf8)),
        "pre_anchor_sha256": try sha256(Data(preAnchorPath.utf8)),
        "privileged_authority_sha256": try sha256(Data(privilegedAuthorityPath.utf8)),
        "settlement_sha256": try sha256(Data(settlementPath.utf8)),
        "stderr_frame_sha256": try sha256(Data(stderrFramePath.utf8)),
        "stdout_frame_sha256": try sha256(Data(stdoutFramePath.utf8)),
        "terminal_final_scan_sha256": try sha256(Data(finalScanPath.utf8)),
        "verify_anchor_claim_sha256": try sha256(Data(verifyAnchorClaimPath.utf8)),
        "verify_anchor_receipt_sha256": try sha256(Data(verifyAnchorReceiptPath.utf8)),
        "verify_anchor_result_sha256": try sha256(Data(verifyAnchorResultPath.utf8)),
        "writer_output_sha256": try sha256(Data(writerOutputPath.utf8)),
    ]
    let phaseObjectRoots: [[String: Any]] = [
        ["role": "invoke-writer-claim", "sha256": try string(invokeRoot["claim_sha256"], code)],
        ["role": "invoke-writer-receipt", "sha256": try string(invokeRoot["receipt_sha256"], code)],
        ["role": "invoke-writer-result", "sha256": try string(invokeRoot["result_sha256"], code)],
        ["role": "verify-anchor-claim", "sha256": try string(verifyRoot["claim_sha256"], code)],
        ["role": "verify-anchor-receipt", "sha256": try string(verifyRoot["receipt_sha256"], code)],
        ["role": "verify-anchor-result", "sha256": try string(verifyRoot["result_sha256"], code)],
    ]
    let marker: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1",
        "authority_sha": authority, "generations": generations,
        "controller_sha256": try string(controllerComponent["sha256"], code),
        "launcher_sha256": try string(launcherComponent["sha256"], code),
        "privileged_authority_sha256": try sha256(authorityReceiptBytes),
        "journal_frame_sha256": try sha256(journalFrameBytes),
        "journal_frame_byte_length": journalFrameBytes.count,
        "complete_event_sha256": try sha256(completeEventBytes),
        "stdout_sha256": try sha256(stdoutBytes), "stdout_byte_length": stdoutBytes.count,
        "stderr_sha256": try sha256(stderrBytes), "stderr_byte_length": stderrBytes.count,
        "terminal_settlement_sha256": try sha256(settlementBytes),
        "complete_result_sha256": try sha256(completeBytes),
        "complete_final_scan_sha256": try sha256(completeFinalScanBytes),
        "pre_anchor_sha256": try sha256(preAnchorBytes),
        "writer_output_sha256": try sha256(writerOutputBytes),
        "terminal_final_scan_sha256": try sha256(finalScanBytes),
        "terminal_phase_objects_sha256": try sha256(compactJSONArrayBytes(phaseObjectRoots)),
        "paths": markerPaths, "terminal_state": "TERMINAL_PASS",
        "receipt_is_commit_marker": true, "normal_executor_authorized": false, "raw_values": false,
    ]
    let markerBytes = try compactJSONBytes(marker)
    for scanID in scanIDs {
        guard try !containsSensitiveSemanticSurface(markerBytes, scanID: scanID) else { try fail("TERMINAL_FINAL_SCAN") }
    }
    if try writeTerminalPhaseArtifact(
        markerBytes, path: markerPath, originalPrivilegedClaimSha256: originalPrivilegedClaimSha256
    ) == "CREATED" { aggregateStatus = "CREATED" }
    let (markerReadback, _) = try readBoundFile(markerPath, mode: 0o444, code: code)
    guard markerReadback == markerBytes else { try fail(code) }
    try syntheticTerminalArtifactCrashHook("MARKER_READBACK")
    guard Darwin.chmod(phaseDirectory, 0o555) == 0,
          Darwin.chmod(generationDirectory, 0o555) == 0 else { try fail(code) }
    try syntheticTerminalArtifactCrashHook("DIRECTORY_FREEZE")
    return (aggregateStatus, try string(settlement["settlement_sha256"], code))
}

// Narrow unprivileged helper used by the Git-bound controller.  It promotes a
// complete private staging directory with the Darwin kernel's no-replace
// primitive; no canonical child pathname is created before this syscall.
private func promoteDirectoryExclusive(_ source: String, _ destination: String) throws {
    let code = "DIRECTORY_PROMOTION"
    guard source.hasPrefix("/"), destination.hasPrefix("/"),
          !source.contains("/../"), !destination.contains("/../"),
          (source as NSString).deletingLastPathComponent == (destination as NSString).deletingLastPathComponent,
          source != destination else { try fail(code) }
    let parent = (source as NSString).deletingLastPathComponent
    let sourceStat = try lstatValue(source, code)
    let parentStat = try lstatValue(parent, code)
    let sourceBefore = physical(sourceStat)
    let parentBefore = physical(parentStat)
    guard (sourceStat.st_mode & S_IFMT) == S_IFDIR, sourceBefore.mode == 0o700,
          sourceBefore.uid == geteuid(), sourceBefore.gid == getegid(),
          (parentStat.st_mode & S_IFMT) == S_IFDIR, sourceBefore.dev == parentBefore.dev else { try fail(code) }
    var destinationStat = stat()
    guard destination.withCString({ Darwin.lstat($0, &destinationStat) }) != 0, errno == ENOENT else { try fail(code) }
    let sourceFD = Darwin.open(source, O_RDONLY | O_NOFOLLOW)
    let parentFD = Darwin.open(parent, O_RDONLY | O_NOFOLLOW)
    guard sourceFD >= 0, parentFD >= 0 else {
        if sourceFD >= 0 { Darwin.close(sourceFD) }
        if parentFD >= 0 { Darwin.close(parentFD) }
        try fail(code)
    }
    defer { Darwin.close(sourceFD); Darwin.close(parentFD) }
    var openedSource = stat()
    var openedParent = stat()
    guard Darwin.fstat(sourceFD, &openedSource) == 0, Darwin.fstat(parentFD, &openedParent) == 0,
          String(openedSource.st_dev) == sourceBefore.dev, String(openedSource.st_ino) == sourceBefore.ino,
          String(openedParent.st_dev) == parentBefore.dev, String(openedParent.st_ino) == parentBefore.ino else { try fail(code) }
    let sourceName = (source as NSString).lastPathComponent
    let destinationName = (destination as NSString).lastPathComponent
    var sourceEntry = stat()
    guard sourceName != ".", sourceName != "..", destinationName != ".", destinationName != "..",
          sourceName.withCString({ Darwin.fstatat(parentFD, $0, &sourceEntry, AT_SYMLINK_NOFOLLOW) }) == 0,
          String(sourceEntry.st_dev) == sourceBefore.dev, String(sourceEntry.st_ino) == sourceBefore.ino else { try fail(code) }
    let promoted = sourceName.withCString { sourcePointer in
        destinationName.withCString { destinationPointer in
            Darwin.renameatx_np(parentFD, sourcePointer, parentFD, destinationPointer, UInt32(RENAME_EXCL))
        }
    }
    guard promoted == 0, Darwin.fsync(parentFD) == 0 else { try fail(code) }
    var destinationFinalStat = stat()
    guard destinationName.withCString({ Darwin.fstatat(parentFD, $0, &destinationFinalStat, AT_SYMLINK_NOFOLLOW) }) == 0 else { try fail(code) }
    let destinationAfter = physical(destinationFinalStat)
    guard (destinationFinalStat.st_mode & S_IFMT) == S_IFDIR, destinationAfter.dev == sourceBefore.dev,
          destinationAfter.ino == sourceBefore.ino, destinationAfter.mode == 0o700,
          destinationAfter.uid == sourceBefore.uid, destinationAfter.gid == sourceBefore.gid else { try fail(code) }
    var vanished = stat()
    guard sourceName.withCString({ Darwin.fstatat(parentFD, $0, &vanished, AT_SYMLINK_NOFOLLOW) }) != 0,
          errno == ENOENT else { try fail(code) }
    print("PROMOTE PASS")
}

// Internal authority helper. The caller must hash-bind this already installed
// binary before invocation. It keeps every ancestor descriptor open and uses
// openat/fstatat for the leaf, so no component is re-resolved from a pathname.
private func descriptorRelativeTransaction() throws {
    let code = "DESCRIPTOR_TRANSACTION"
    guard let input = try FileHandle.standardInput.readToEnd(), !input.isEmpty,
          let decoded = try JSONSerialization.jsonObject(with: input) as? [String: Any] else { try fail(code) }
    try exactKeys(decoded, [
        "allowed_directory_modes", "bytes_base64", "expected_gid", "expected_mode", "expected_uid",
        "make_immutable", "operation", "purpose", "relative_path", "require_immutable", "root", "schema_version",
    ], code)
    guard try integer(decoded["schema_version"], code) == 1,
          try string(decoded["purpose"], code) == "CI3_DESCRIPTOR_RELATIVE_TRANSACTION_V1" else { try fail(code) }
    let root = try string(decoded["root"], code)
    let relativePath = try string(decoded["relative_path"], code)
    let operation = try string(decoded["operation"], code)
    let expectedUID = uid_t(try integer(decoded["expected_uid"], code))
    let expectedGID = gid_t(try integer(decoded["expected_gid"], code))
    let expectedMode = mode_t(try integer(decoded["expected_mode"], code))
    let makeImmutable = try bool(decoded["make_immutable"], code)
    let requireImmutable = try bool(decoded["require_immutable"], code)
    let allowedModes = Set(try array(decoded["allowed_directory_modes"], code).map { mode_t(try integer($0, code)) })
    let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard root.hasPrefix("/"), !root.contains("/../"), !relativePath.hasPrefix("/"), !relativePath.contains(".."),
          !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
          ["read", "create-exclusive"].contains(operation), !allowedModes.isEmpty,
          !makeImmutable || operation == "create-exclusive" else { try fail(code) }
    let rootFD = Darwin.open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard rootFD >= 0 else { try fail("DESCRIPTOR_CHAIN") }
    var descriptors = [rootFD]
    defer { for descriptor in descriptors.reversed() { Darwin.close(descriptor) } }
    var currentFD = rootFD
    var directoryStats = [try fstatValue(rootFD, "DESCRIPTOR_CHAIN")]
    for component in parts.dropLast() {
        let nextFD = component.withCString { Darwin.openat(currentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
        guard nextFD >= 0 else { try fail("DESCRIPTOR_CHAIN") }
        descriptors.append(nextFD)
        currentFD = nextFD
        directoryStats.append(try fstatValue(nextFD, "DESCRIPTOR_CHAIN"))
    }
    for observed in directoryStats {
        let mode = observed.st_mode & 0o777
        guard (observed.st_mode & S_IFMT) == S_IFDIR, observed.st_uid == expectedUID,
              observed.st_gid == expectedGID, allowedModes.contains(mode), mode & 0o022 == 0 else {
            try fail("DESCRIPTOR_CHAIN")
        }
    }
    let leaf = parts.last!
    var leafFD: Int32 = -1
    if operation == "read" {
        leafFD = leaf.withCString { Darwin.openat(currentFD, $0, O_RDONLY | O_NOFOLLOW) }
    } else {
        leafFD = leaf.withCString { Darwin.openat(currentFD, $0, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, expectedMode) }
        if leafFD < 0, errno == EEXIST { try fail("DESCRIPTOR_NO_CLOBBER") }
    }
    guard leafFD >= 0 else { try fail("DESCRIPTOR_LEAF") }
    defer { Darwin.close(leafFD) }
    if operation == "create-exclusive" {
        guard let payload = Data(base64Encoded: try string(decoded["bytes_base64"], code), options: []) else { try fail(code) }
        var offset = 0
        try payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            while offset < payload.count {
                let count = Darwin.write(leafFD, base.advanced(by: offset), payload.count - offset)
                guard count > 0 else { try fail("DESCRIPTOR_LEAF") }
                offset += count
            }
        }
        guard Darwin.fchmod(leafFD, expectedMode) == 0, Darwin.fsync(leafFD) == 0 else { try fail("DESCRIPTOR_LEAF") }
        if makeImmutable {
            guard Darwin.fchflags(leafFD, UInt32(UF_IMMUTABLE)) == 0 else { try fail("DESCRIPTOR_LEAF") }
        }
        guard Darwin.fsync(currentFD) == 0, Darwin.lseek(leafFD, 0, SEEK_SET) == 0 else { try fail("DESCRIPTOR_LEAF") }
    }
    let before = try fstatValue(leafFD, "DESCRIPTOR_LEAF")
    let beforePhysical = physical(before)
    guard (before.st_mode & S_IFMT) == S_IFREG, before.st_uid == expectedUID, before.st_gid == expectedGID,
          before.st_nlink == 1, before.st_mode & 0o777 == expectedMode else { try fail("DESCRIPTOR_LEAF") }
    let immutable = (before.st_flags & UInt32(UF_IMMUTABLE)) != 0
    if requireImmutable && !immutable { try fail("DESCRIPTOR_LEAF") }
    var output = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
        let count = Darwin.read(leafFD, &buffer, buffer.count)
        if count < 0 { try fail("DESCRIPTOR_LEAF") }
        if count == 0 { break }
        output.append(buffer, count: count)
        if output.count > 4 * 1024 * 1024 { try fail("DESCRIPTOR_LEAF") }
    }
    let after = try fstatValue(leafFD, "DESCRIPTOR_LEAF")
    var relative = stat()
    guard leaf.withCString({ Darwin.fstatat(currentFD, $0, &relative, AT_SYMLINK_NOFOLLOW) }) == 0,
          physical(after) == beforePhysical, physical(relative) == beforePhysical else { try fail("DESCRIPTOR_LEAF") }
    let observed = physical(after)
    let response: [String: Any] = [
        "bytes_base64": output.base64EncodedString(), "immutable": immutable,
        "metadata": [
            "dev": observed.dev, "gid": Int(observed.gid), "ino": observed.ino,
            "mode": Int(observed.mode), "mtime_ns": observed.mtimeNS, "nlink": Int(observed.nlink),
            "size": Int(observed.size), "uid": Int(observed.uid),
        ],
    ]
    FileHandle.standardOutput.write(try compactJSONBytes(response))
}

private let publisher1Targets: [(String, String, Int)] = [
    ("node-runtime", "runtime/node", 0o555),
    ("controller", "runtime/ci3-bridge-controller.mjs", 0o555),
    ("launcher-runtime", "runtime/ci3-bridge-launcher.zsh", 0o555),
    ("launcher-bootstrap-authority", "runtime/launcher-bootstrap.authority.v1", 0o444),
    ("launch-attestation", "runtime/launch-attestation.json", 0o444),
    ("authority-manifest", "runtime/authority-manifest.v1", 0o444),
    ("operation-authority", "mac-operation-authority.v1.json", 0o444),
    ("human-authorization", "human-authorization.receipt.json", 0o444),
    ("vps-pass", "vps-operation-authority.pass.json", 0o444),
    ("vps-issuer-authority", "vps-issuer-authority.receipt.json", 0o444),
    ("publisher-input-manifest", "publisher-input.manifest.json", 0o444),
    ("ssh-config", "ssh-snapshots/{controller}/ssh_config", 0o444),
    ("ssh-known-hosts", "ssh-snapshots/{controller}/known_hosts", 0o444),
    ("ssh-private-key", "ssh-snapshots/{controller}/id_ed25519", 0o400),
    ("ssh-public-key", "ssh-snapshots/{controller}/id_ed25519.pub", 0o444),
    ("ssh-trust-descriptor", "ssh-snapshots/{controller}/trust-descriptor.json", 0o444),
]

private func readDescriptorBytes(_ descriptor: Int32, _ code: String) throws -> Data {
    guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else { try fail(code) }
    var bytes = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        if count < 0 { try fail(code) }
        if count == 0 { break }
        bytes.append(buffer, count: count)
        if bytes.count > 16 * 1024 * 1024 { try fail(code) }
    }
    return bytes
}

private func writeExclusiveAt(
    _ parentFD: Int32, _ name: String, bytes: Data, mode: mode_t,
    makeImmutable: Bool = true, code: String
) throws {
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { try fail(code) }
    let descriptor = name.withCString { Darwin.openat(parentFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode) }
    guard descriptor >= 0 else { try fail(code) }
    defer { Darwin.close(descriptor) }
    var offset = 0
    let written = bytes.withUnsafeBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return bytes.isEmpty }
        while offset < bytes.count {
            let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
            if count <= 0 { return false }
            offset += count
        }
        return true
    }
    guard written, Darwin.fchmod(descriptor, mode) == 0 else { try fail(code) }
#if !CI3_SYNTHETIC_TEST && !CI3_DARWIN_PROMOTION_PROBE
    guard Darwin.fchown(descriptor, 0, 0) == 0 else { try fail(code) }
#endif
#if !CI3_SYNTHETIC_TEST
    if makeImmutable, Darwin.fchflags(descriptor, UInt32(UF_IMMUTABLE)) != 0 { try fail(code) }
#endif
    guard Darwin.fsync(descriptor) == 0, Darwin.fsync(parentFD) == 0 else { try fail(code) }
}

private func openDirectoryAt(_ parentFD: Int32, _ name: String, create: Bool, code: String) throws -> Int32 {
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { try fail(code) }
    if create {
        let created = name.withCString { Darwin.mkdirat(parentFD, $0, 0o700) }
        if created != 0, errno != EEXIST { try fail(code) }
    }
    let descriptor = name.withCString { Darwin.openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
    guard descriptor >= 0 else { try fail(code) }
    let observed = try fstatValue(descriptor, code)
    guard (observed.st_mode & S_IFMT) == S_IFDIR,
          observed.st_mode & 0o022 == 0 else { Darwin.close(descriptor); try fail(code) }
    return descriptor
}

private func openAbsoluteDirectoryChain(_ absolutePath: String, code: String) throws -> [Int32] {
    guard absolutePath.hasPrefix("/"), !absolutePath.contains("/../") else { try fail(code) }
    let rootFD = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard rootFD >= 0 else { try fail(code) }
    var descriptors = [rootFD]
    var currentFD = rootFD
    do {
        for component in absolutePath.split(separator: "/").map(String.init) {
            let next = component.withCString { Darwin.openat(currentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
            guard next >= 0 else { try fail(code) }
            descriptors.append(next)
            currentFD = next
        }
        for descriptor in descriptors {
            let observed = try fstatValue(descriptor, code)
            guard (observed.st_mode & S_IFMT) == S_IFDIR, observed.st_mode & 0o022 == 0 else { try fail(code) }
        }
        return descriptors
    } catch {
        for descriptor in descriptors.reversed() { Darwin.close(descriptor) }
        throw error
    }
}

private func publisher1DirectoryPaths(_ entries: [[String: Any]], _ code: String) throws -> [[String]] {
    var unique = Set<String>()
    for entry in entries {
        let parts = try string(entry["destination_relative_path"], code).split(separator: "/").map(String.init)
        for count in 1..<parts.count { unique.insert(parts.prefix(count).joined(separator: "/")) }
    }
    return unique.map { $0.split(separator: "/").map(String.init) }.sorted {
        if $0.count != $1.count { return $0.count > $1.count }
        return $0.joined(separator: "/") < $1.joined(separator: "/")
    }
}

private func freezePublisher1Directory(_ descriptor: Int32, _ code: String) throws {
#if !CI3_SYNTHETIC_TEST && !CI3_DARWIN_PROMOTION_PROBE
    guard Darwin.fchown(descriptor, 0, 0) == 0 else { try fail(code) }
#endif
    guard Darwin.fchmod(descriptor, 0o555) == 0, Darwin.fsync(descriptor) == 0 else { try fail(code) }
#if !CI3_SYNTHETIC_TEST
    guard Darwin.fchflags(descriptor, UInt32(UF_IMMUTABLE)) == 0 else { try fail(code) }
#endif
}

private func freezePublisher1PublishedTree(
    parentFD: Int32, finalName: String, entries: [[String: Any]], code: String
) throws {
    let finalFD = try openDirectoryAt(parentFD, finalName, create: false, code: code)
    defer { Darwin.close(finalFD) }
    for entry in entries {
        let parts = try string(entry["destination_relative_path"], code).split(separator: "/").map(String.init)
        guard !parts.isEmpty else { try fail(code) }
        var descriptors: [Int32] = []
        var currentFD = finalFD
        defer { for descriptor in descriptors.reversed() { Darwin.close(descriptor) } }
        for component in parts.dropLast() {
            let next = try openDirectoryAt(currentFD, component, create: false, code: code)
            descriptors.append(next)
            currentFD = next
        }
        let leafFD = parts.last!.withCString { Darwin.openat(currentFD, $0, O_RDONLY | O_NOFOLLOW) }
        guard leafFD >= 0 else { try fail(code) }
        defer { Darwin.close(leafFD) }
        let observed = try fstatValue(leafFD, code)
        let bytes = try readDescriptorBytes(leafFD, code)
        let expectedMode = try integer(entry["mode"], code)
        guard (observed.st_mode & S_IFMT) == S_IFREG, observed.st_nlink == 1,
              Int(observed.st_mode & 0o777) == expectedMode,
              try sha256(bytes) == string(entry["source_sha256"], code) else { try fail(code) }
#if !CI3_SYNTHETIC_TEST && !CI3_DARWIN_PROMOTION_PROBE
        guard Darwin.fchown(leafFD, 0, 0) == 0 else { try fail(code) }
#endif
        guard Darwin.fchmod(leafFD, mode_t(expectedMode)) == 0,
              Darwin.fsync(leafFD) == 0 else { try fail(code) }
#if !CI3_SYNTHETIC_TEST
        guard Darwin.fchflags(leafFD, UInt32(UF_IMMUTABLE)) == 0 else { try fail(code) }
#endif
    }
    try freezePublisher1Tree(finalFD, entries: entries, code: code)
    guard Darwin.fsync(finalFD) == 0, Darwin.fsync(parentFD) == 0 else { try fail(code) }
}

private func freezePublisher1Tree(_ rootFD: Int32, entries: [[String: Any]], code: String) throws {
    for parts in try publisher1DirectoryPaths(entries, code) {
        var descriptors: [Int32] = []
        var currentFD = rootFD
        defer { for descriptor in descriptors.reversed() { Darwin.close(descriptor) } }
        for component in parts {
            let next = try openDirectoryAt(currentFD, component, create: false, code: code)
            descriptors.append(next)
            currentFD = next
        }
        try freezePublisher1Directory(currentFD, code)
    }
    try freezePublisher1Directory(rootFD, code)
}

private func validatePublisher1Directories(_ rootFD: Int32, entries: [[String: Any]], code: String) throws {
    let paths = [[]] + (try publisher1DirectoryPaths(entries, code)).reversed()
    for parts in paths {
        var descriptors: [Int32] = []
        var currentFD = rootFD
        defer { for descriptor in descriptors.reversed() { Darwin.close(descriptor) } }
        for component in parts {
            let next = try openDirectoryAt(currentFD, component, create: false, code: code)
            descriptors.append(next)
            currentFD = next
        }
        let observed = try fstatValue(currentFD, code)
        guard (observed.st_mode & S_IFMT) == S_IFDIR, observed.st_mode & 0o777 == 0o555 else { try fail(code) }
#if !CI3_SYNTHETIC_TEST && !CI3_DARWIN_PROMOTION_PROBE
        guard observed.st_uid == 0, observed.st_gid == 0,
              (observed.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try fail(code) }
#elseif CI3_DARWIN_PROMOTION_PROBE
        guard observed.st_uid == geteuid(), observed.st_gid == getegid(),
              (observed.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try fail(code) }
#endif
    }
}

private func observePublisher1Tree(parentFD: Int32, finalName: String, entries: [[String: Any]], code: String) throws -> [[String: Any]] {
    let finalFD = try openDirectoryAt(parentFD, finalName, create: false, code: code)
    defer { Darwin.close(finalFD) }
    try validatePublisher1Directories(finalFD, entries: entries, code: code)
    var observations: [[String: Any]] = []
    for entry in entries {
        let relative = try string(entry["destination_relative_path"], code)
        let parts = relative.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { try fail(code) }
        var ownedDescriptors: [Int32] = []
        var currentFD = finalFD
        defer { for descriptor in ownedDescriptors.reversed() { Darwin.close(descriptor) } }
        for component in parts.dropLast() {
            let next = try openDirectoryAt(currentFD, component, create: false, code: code)
            ownedDescriptors.append(next)
            currentFD = next
        }
        let leaf = parts.last!
        let leafFD = leaf.withCString { Darwin.openat(currentFD, $0, O_RDONLY | O_NOFOLLOW) }
        guard leafFD >= 0 else { try fail(code) }
        let before = try fstatValue(leafFD, code)
        let bytes = try readDescriptorBytes(leafFD, code)
        let after = try fstatValue(leafFD, code)
        Darwin.close(leafFD)
        let expectedMode = try integer(entry["mode"], code)
        guard physical(before) == physical(after), (after.st_mode & S_IFMT) == S_IFREG,
              after.st_nlink == 1, Int(after.st_mode & 0o777) == expectedMode,
              try sha256(bytes) == string(entry["source_sha256"], code) else { try fail(code) }
#if !CI3_SYNTHETIC_TEST && !CI3_DARWIN_PROMOTION_PROBE
        guard after.st_uid == 0, after.st_gid == 0,
              (after.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try fail(code) }
#elseif CI3_DARWIN_PROMOTION_PROBE
        guard after.st_uid == geteuid(), after.st_gid == getegid(),
              (after.st_flags & UInt32(UF_IMMUTABLE)) != 0 else { try fail(code) }
#endif
        observations.append([
            "role": try string(entry["role"], code), "sha256": try sha256(bytes),
            "identity_sha256": try physicalIdentityHash(physical(after)), "mode": expectedMode,
        ])
    }
    return observations
}

private func publisher1RequestBytes(_ arguments: [String]) throws -> (Data, Physical?, String?) {
    let code = "PUBLISHER1_TRANSACTION"
    if arguments.isEmpty {
#if CI3_SYNTHETIC_TEST
        guard let input = try FileHandle.standardInput.readToEnd(), !input.isEmpty else { try fail(code) }
        return (input, nil, nil)
#else
        try fail("MODE_INVALID")
#endif
    }
    guard arguments.count == 2, arguments[0].hasPrefix("/"), !arguments[0].contains("/../"),
          isHex(arguments[1], count: 64) else { try fail(code) }
    let descriptor = Darwin.open(arguments[0], O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { try fail(code) }
    defer { Darwin.close(descriptor) }
    let before = try fstatValue(descriptor, code)
#if CI3_SYNTHETIC_TEST
    let expectedMode: mode_t = 0o600
    let expectedUID = geteuid()
    let expectedGID = getegid()
#else
    let expectedMode: mode_t = 0o600
#endif
    guard (before.st_mode & S_IFMT) == S_IFREG, before.st_nlink == 1,
          before.st_mode & 0o777 == expectedMode else { try fail(code) }
#if CI3_SYNTHETIC_TEST
    guard before.st_uid == expectedUID, before.st_gid == expectedGID else { try fail(code) }
#else
    guard before.st_uid != 0, before.st_gid != 0 else { try fail(code) }
#endif
    let bytes = try readDescriptorBytes(descriptor, code)
    let after = try fstatValue(descriptor, code)
    guard physical(before) == physical(after), try sha256(bytes) == arguments[1] else { try fail(code) }
    return (bytes, physical(after), URL(fileURLWithPath: arguments[0]).standardized.path)
}

#if CI3_DARWIN_PROMOTION_PROBE
private func publisher1PromotionProbe(_ transactionRoot: String) throws {
    let code = "PUBLISHER1_PROMOTION_PROBE"
    guard transactionRoot.hasPrefix("/"), !transactionRoot.contains("/../") else { try fail(code) }
    guard transactionRoot.withCString({ Darwin.mkdir($0, 0o700) }) == 0 else { try fail(code) }
    let parentFD = Darwin.open(transactionRoot, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard parentFD >= 0 else { try fail(code) }
    defer { Darwin.close(parentFD) }
    let bytes = Data("darwin-promotion-probe\n".utf8)
    let entries: [[String: Any]] = [[
        "role": "probe", "source_sha256": try sha256(bytes),
        "destination_relative_path": "probe.txt", "mode": 0o444,
    ]]
    guard "staging".withCString({ Darwin.mkdirat(parentFD, $0, 0o700) }) == 0 else { try fail(code) }
    let stagingFD = try openDirectoryAt(parentFD, "staging", create: false, code: code)
    try writeExclusiveAt(stagingFD, "probe.txt", bytes: bytes, mode: 0o444, makeImmutable: false, code: code)
    guard Darwin.fsync(stagingFD) == 0, Darwin.fsync(parentFD) == 0 else { Darwin.close(stagingFD); try fail(code) }
    Darwin.close(stagingFD)
    let promoted = "staging".withCString { source in
        "final".withCString { destination in
            Darwin.renameatx_np(parentFD, source, parentFD, destination, UInt32(RENAME_EXCL))
        }
    }
    guard promoted == 0, Darwin.fsync(parentFD) == 0 else { try fail(code) }
    try freezePublisher1PublishedTree(parentFD: parentFD, finalName: "final", entries: entries, code: code)
    _ = try observePublisher1Tree(parentFD: parentFD, finalName: "final", entries: entries, code: code)
    _ = try observePublisher1Tree(parentFD: parentFD, finalName: "final", entries: entries, code: code)
    guard "raced".withCString({ Darwin.mkdirat(parentFD, $0, 0o700) }) == 0 else { try fail(code) }
    let rejected = "raced".withCString { source in
        "final".withCString { destination in
            Darwin.renameatx_np(parentFD, source, parentFD, destination, UInt32(RENAME_EXCL))
        }
    }
    guard rejected != 0, errno == EEXIST else { try fail(code) }
    print("PUBLISHER1_PROMOTION_PROBE PASS status=CREATED recovery=EXISTS_VERIFIED no_clobber=REJECTED")
}
#endif

#if !CI3_SYNTHETIC_TEST
private func validatePublisher1Bootstrap(authority: String, controllerGeneration: String) throws -> (Data, [String: Any]) {
    let code = "STOP_PRE_AUTHORITY"
    let root = "/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/\(authority)/\(controllerGeneration)"
    let authorityPath = "\(root)/publisher1-materializer.authority.json"
    let issuerPath = "\(root)/vps-issuer-authority.receipt.json"
    let binaryPath = "\(root)/runtime/ci3-terminal-anchor-writer"
    guard URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path == binaryPath else { try fail(code) }
    let (authorityBytes, authorityPhysical) = try readBoundFile(authorityPath, mode: 0o444, code: code)
    let (issuerBytes, issuerPhysical) = try readBoundFile(issuerPath, mode: 0o444, code: code)
    let (binaryBytes, binaryPhysical) = try readBoundFile(binaryPath, mode: 0o555, code: code)
    for observed in [authorityPhysical, issuerPhysical, binaryPhysical] {
        guard observed.uid == 0, observed.gid == 0, observed.nlink == 1,
              (observed.flags & UInt32(UF_IMMUTABLE)) != 0 else { try fail(code) }
    }
    let record = try jsonObject(authorityBytes, code)
    try exactKeys(record, [
        "allowed_environment", "authority_sha", "controller_generation_id",
        "issuer_authority_sha256", "materializer_path", "materializer_path_sha256",
        "materializer_sha256", "normal_executor_authorized", "purpose", "raw_values",
        "receiver_leaves", "receiver_root_identity_sha256", "receiver_root_path_sha256",
        "request_gid", "request_identity_sha256", "request_mode", "request_nlink",
        "request_path_sha256", "request_sha256", "request_uid",
        "schema_version", "writer_source_sha256",
    ], code)
    let environment = try dictionary(record["allowed_environment"], code)
    try exactKeys(environment, ["HOME", "LANG", "LC_ALL", "PATH"], code)
    guard try integer(record["schema_version"], code) == 2,
          try string(record["purpose"], code) == "CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2",
          try string(record["authority_sha"], code) == authority,
          try string(record["controller_generation_id"], code) == controllerGeneration,
          try string(record["materializer_path"], code) == binaryPath,
          try string(record["materializer_path_sha256"], code) == sha256(Data(binaryPath.utf8)),
          try string(record["materializer_sha256"], code) == sha256(binaryBytes),
          try string(record["issuer_authority_sha256"], code) == sha256(issuerBytes),
          isHex(try string(record["writer_source_sha256"], code), count: 64),
          isHex(try string(record["request_path_sha256"], code), count: 64),
          isHex(try string(record["request_sha256"], code), count: 64),
          isHex(try string(record["request_identity_sha256"], code), count: 64),
          try integer(record["request_uid"], code) > 0,
          try integer(record["request_gid"], code) > 0,
          try integer(record["request_mode"], code) == 0o600,
          try integer(record["request_nlink"], code) == 1,
          isHex(try string(record["receiver_root_path_sha256"], code), count: 64),
          isHex(try string(record["receiver_root_identity_sha256"], code), count: 64),
          try array(record["receiver_leaves"], code).count == publisher1Targets.count,
          try bool(record["normal_executor_authorized"], code) == false,
          try bool(record["raw_values"], code) == false,
          try string(environment["HOME"], code) == "/var/empty",
          try string(environment["LANG"], code) == "C",
          try string(environment["LC_ALL"], code) == "C",
          try string(environment["PATH"], code) == "/usr/bin:/bin" else { try fail(code) }
    return (issuerBytes, record)
}

private func validatePublisher1SemanticSources(
    _ sources: [(entry: [String: Any], descriptor: Int32, bytes: Data, physical: Physical)],
    authority: String, remoteGeneration: String, controllerGeneration: String,
    receiverManifestHash: String, trustedIssuerBytes: Data
) throws {
    let code = "PUBLISHER1_SEMANTICS"
    let byRole = Dictionary(uniqueKeysWithValues: try sources.map {
        (try string($0.entry["role"], code), $0.bytes)
    })
    func bytes(_ role: String) throws -> Data {
        guard let value = byRole[role] else { try fail(code) }
        return value
    }
    func object(_ role: String) throws -> [String: Any] { try jsonObject(bytes(role), code) }

    let issuerBytes = try bytes("vps-issuer-authority")
    guard issuerBytes == trustedIssuerBytes else { try fail("STOP_PRE_AUTHORITY") }
    let issuer = try object("vps-issuer-authority")
    try exactKeys(issuer, [
        "allowed_pass_purpose", "authority_sha", "issuer_generation_id", "issuer_identity_sha256",
        "normal_executor_authorized", "public_key_algorithm", "public_key_raw_base64", "public_key_sha256",
        "purpose", "raw_values", "schema_version",
    ], code)
    guard let issuerKey = Data(base64Encoded: try string(issuer["public_key_raw_base64"], code)), issuerKey.count == 32,
          try integer(issuer["schema_version"], code) == 1,
          try string(issuer["purpose"], code) == "CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1",
          try string(issuer["authority_sha"], code) == authority,
          isGeneration(try string(issuer["issuer_generation_id"], code), prefix: "issuer"),
          try string(issuer["public_key_algorithm"], code) == "Ed25519",
          try string(issuer["public_key_sha256"], code) == sha256(issuerKey),
          try string(issuer["allowed_pass_purpose"], code) == "CI3_VPS_OPERATION_AUTHORITY_PASS_V1",
          try bool(issuer["normal_executor_authorized"], code) == false,
          try bool(issuer["raw_values"], code) == false else { try fail(code) }

    let pass = try object("vps-pass")
    var signedPayload = pass
    let signatureText = try string(signedPayload.removeValue(forKey: "signature_base64"), code)
    let signedPayloadHash = try string(signedPayload.removeValue(forKey: "signed_payload_sha256"), code)
    let signedPayloadBytes = try compactJSONBytes(signedPayload)
    guard let signature = Data(base64Encoded: signatureText), signature.count == 64,
          try string(pass["purpose"], code) == "CI3_VPS_OPERATION_AUTHORITY_PASS_V1",
          try string(pass["authority_sha"], code) == authority,
          try string(pass["remote_generation_id"], code) == remoteGeneration,
          try string(pass["controller_generation_id"], code) == controllerGeneration,
          try string(pass["issuer_authority_sha256"], code) == sha256(issuerBytes),
          try string(pass["issuer_key_sha256"], code) == sha256(issuerKey),
          signedPayloadHash == (try sha256(signedPayloadBytes)),
          try Curve25519.Signing.PublicKey(rawRepresentation: issuerKey).isValidSignature(signature, for: signedPayloadBytes),
          try integer(pass["attempt"], code) == 1, try bool(pass["retry"], code) == false,
          try bool(pass["raw_values"], code) == false else { try fail(code) }

    let operationBytes = try bytes("operation-authority")
    let operation = try object("operation-authority")
    let operationContext = try dictionary(operation["context"], code)
    let operationAuthority = try dictionary(operationContext["authority"], code)
    let generations = try dictionary(operationContext["generations"], code)
    let components = try dictionary(operationAuthority["components"], code)
    let ssh = try dictionary(operation["ssh"], code)
    guard try string(operation["purpose"], code) == "CI3_MAC_OPERATION_AUTHORITY_V1",
          try string(operationAuthority["commit"], code) == authority,
          try string(generations["remote"], code) == remoteGeneration,
          try string(generations["controller"], code) == controllerGeneration,
          try string(pass["operation_authority_sha256"], code) == sha256(operationBytes),
          try string(pass["node_candidate_sha256"], code) == sha256(bytes("node-runtime")),
          try string(operationAuthority["manifest_sha256"], code) == sha256(bytes("authority-manifest")),
          try string(dictionary(components["controller"], code)["sha256"], code) == sha256(bytes("controller")),
          try string(dictionary(components["launcher"], code)["sha256"], code) == sha256(bytes("launcher-runtime")),
          try string(ssh["config_sha256"], code) == sha256(bytes("ssh-config")),
          try string(ssh["known_hosts_sha256"], code) == sha256(bytes("ssh-known-hosts")),
          try string(ssh["identity_sha256"], code) == sha256(bytes("ssh-private-key")),
          try string(ssh["identity_public_key_sha256"], code) == sha256(bytes("ssh-public-key")),
          try string(ssh["trust_descriptor_sha256"], code) == sha256(bytes("ssh-trust-descriptor")) else { try fail(code) }

    let publisherBytes = try bytes("publisher-input-manifest")
    let publisher = try object("publisher-input-manifest")
    let publisherEntries = try array(publisher["entries"], code).map { try dictionary($0, code) }
    let transportRoles = Array(publisher1Targets.map(\.0).prefix(3)) + [
        "launch-attestation", "authority-manifest", "operation-authority", "ssh-config",
        "ssh-known-hosts", "ssh-private-key", "ssh-public-key", "ssh-trust-descriptor",
    ]
    guard receiverManifestHash == (try sha256(publisherBytes)),
          try string(publisher["purpose"], code) == "CI3_VPS_PUBLISHER_INPUT_MANIFEST_V2",
          try string(publisher["authority_sha"], code) == authority,
          try string(publisher["remote_generation_id"], code) == remoteGeneration,
          try string(publisher["controller_generation_id"], code) == controllerGeneration,
          publisherEntries.count == transportRoles.count,
          try string(publisher["transfer_payload_sha256"], code) == sha256(compactJSONArrayBytes(publisherEntries)),
          try string(pass["publisher_input_manifest_sha256"], code) == sha256(publisherBytes),
          try string(pass["transfer_payload_sha256"], code) == string(publisher["transfer_payload_sha256"], code) else { try fail(code) }
    for (index, role) in transportRoles.enumerated() {
        let entry = publisherEntries[index]
        guard try string(entry["role"], code) == role,
              try string(entry["sha256"], code) == sha256(bytes(role)),
              isHex(try string(entry["path_sha256"], code), count: 64) else { try fail(code) }
    }

    let attestationBytes = try bytes("launch-attestation")
    let attestation = try object("launch-attestation")
    let attestationComponents = try dictionary(attestation["components"], code)
    let tools = try dictionary(attestation["tools"], code)
    guard try string(attestation["authority_sha"], code) == authority,
          try string(attestation["controller_generation_id"], code) == controllerGeneration,
          try string(attestation["authority_manifest_sha256"], code) == sha256(bytes("authority-manifest")),
          try string(dictionary(attestationComponents["controller"], code)["sha256"], code) == sha256(bytes("controller")),
          try string(dictionary(attestationComponents["launcher"], code)["sha256"], code) == sha256(bytes("launcher-runtime")),
          try string(dictionary(tools["node"], code)["binary_sha256"], code) == sha256(bytes("node-runtime")) else { try fail(code) }

    let human = try object("human-authorization")
    guard try string(human["purpose"], code) == "CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V1",
          try string(human["approved_action"], code) == "PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY",
          try string(human["authority_sha"], code) == authority,
          try string(human["operation_authority_sha256"], code) == sha256(operationBytes),
          try string(human["publisher_input_manifest_sha256"], code) == sha256(publisherBytes),
          try string(human["vps_operation_authority_pass_sha256"], code) == sha256(bytes("vps-pass")),
          try string(human["node_binary_sha256"], code) == sha256(bytes("node-runtime")),
          try integer(human["attempt"], code) == 1, try bool(human["retry"], code) == false,
          try bool(human["raw_values"], code) == false else { try fail(code) }

    let nodeHash = try sha256(bytes("node-runtime"))
    let controllerHash = try sha256(bytes("controller"))
    let launcherHash = try sha256(bytes("launcher-runtime"))
    let authorityManifestHash = try sha256(bytes("authority-manifest"))
    let launcherAuthority = Data([
        "CI3_EXTERNAL_LAUNCHER_AUTHORITY_V1", "authority_sha \(authority)",
        "controller_generation_id \(controllerGeneration)", "node_sha256 \(nodeHash)",
        "controller_sha256 \(controllerHash)", "launcher_sha256 \(launcherHash)",
        "launch_attestation_sha256 \(try sha256(attestationBytes))", "authority_manifest_sha256 \(authorityManifestHash)",
        "allowed_modes plan,verify-simulator,verify-ssh,fetch,install-simulator,scan,write-terminal-anchor,resume,status,publish-privileged-writer-authority",
        "raw_values false", "",
    ].joined(separator: "\n").utf8)
    let installedLauncherAuthority = try bytes("launcher-bootstrap-authority")
    guard launcherAuthority == installedLauncherAuthority else { try fail(code) }
}
#endif

private func publisher1Transaction(arguments: [String] = []) throws {
    let code = "PUBLISHER1_TRANSACTION"
    let (input, requestPhysical, requestPath) = try publisher1RequestBytes(arguments)
    let request = try jsonObject(input, code)
    try exactKeys(request, [
        "attempt", "authority_sha", "controller_generation_id", "destination_parent", "entries",
        "purpose", "raw_values", "receiver_manifest_sha256", "receiver_root", "remote_generation_id",
        "retry", "schema_version", "state_root",
    ], code)
    let authority = try string(request["authority_sha"], code)
    let remoteGeneration = try string(request["remote_generation_id"], code)
    let controllerGeneration = try string(request["controller_generation_id"], code)
    let receiverRoot = try string(request["receiver_root"], code)
    let destinationParent = try string(request["destination_parent"], code)
    let stateRoot = try string(request["state_root"], code)
    let receiverManifestHash = try string(request["receiver_manifest_sha256"], code)
    guard try integer(request["schema_version"], code) == 1,
          try string(request["purpose"], code) == "CI3_PUBLISHER1_DESCRIPTOR_TRANSACTION_V1",
          isHex(authority, count: 40), isGeneration(remoteGeneration, prefix: "remote"),
          isGeneration(controllerGeneration, prefix: "controller"),
          isHex(receiverManifestHash, count: 64), try integer(request["attempt"], code) == 1,
          try bool(request["retry"], code) == false, try bool(request["raw_values"], code) == false,
          receiverRoot.hasPrefix("/"), destinationParent.hasPrefix("/"), stateRoot.hasPrefix("/"),
          !receiverRoot.contains("/../"), !destinationParent.contains("/../"), !stateRoot.contains("/../") else { try fail(code) }
#if !CI3_SYNTHETIC_TEST
    let (trustedIssuerBytes, materializerAuthority) = try validatePublisher1Bootstrap(
        authority: authority, controllerGeneration: controllerGeneration
    )
    guard getuid() == 0, geteuid() == 0,
          destinationParent == "/Library/Application Support/Agentempp/ci3-controller-authority",
          stateRoot == "/Library/Application Support/Agentempp/ci3-publisher1-state/\(authority)/\(controllerGeneration)",
          let boundRequestPhysical = requestPhysical, let boundRequestPath = requestPath,
          try string(materializerAuthority["request_path_sha256"], code) == sha256(Data(boundRequestPath.utf8)),
          try string(materializerAuthority["request_sha256"], code) == sha256(input),
          try string(materializerAuthority["request_identity_sha256"], code) == physicalIdentityHash(boundRequestPhysical),
          try integer(materializerAuthority["request_uid"], code) == Int(boundRequestPhysical.uid),
          try integer(materializerAuthority["request_gid"], code) == Int(boundRequestPhysical.gid),
          try integer(materializerAuthority["request_mode"], code) == Int(boundRequestPhysical.mode),
          try integer(materializerAuthority["request_nlink"], code) == Int(boundRequestPhysical.nlink),
          try string(materializerAuthority["receiver_root_path_sha256"], code) == sha256(Data(receiverRoot.utf8)) else {
        try fail("STOP_PRE_AUTHORITY")
    }
#endif
    let rawEntries = try array(request["entries"], code)
    guard rawEntries.count == publisher1Targets.count else { try fail(code) }
    var entries: [[String: Any]] = []
    for (index, raw) in rawEntries.enumerated() {
        let entry = try dictionary(raw, code)
        try exactKeys(entry, [
            "destination_relative_path", "mode", "role", "source_dev", "source_gid",
            "source_identity_sha256", "source_ino", "source_mode", "source_mtime_ns",
            "source_nlink", "source_path", "source_path_sha256", "source_sha256",
            "source_size", "source_uid",
        ], code)
        let expected = publisher1Targets[index]
        let expectedRelative = expected.1.replacingOccurrences(of: "{controller}", with: controllerGeneration)
        let role = try string(entry["role"], code)
        let sourcePath = (receiverRoot as NSString).appendingPathComponent("\(role).payload")
        guard role == expected.0, try string(entry["destination_relative_path"], code) == expectedRelative,
              try integer(entry["mode"], code) == expected.2,
              try string(entry["source_path"], code) == sourcePath,
              try string(entry["source_path_sha256"], code) == sha256(Data(sourcePath.utf8)),
              isHex(try string(entry["source_sha256"], code), count: 64),
              isHex(try string(entry["source_identity_sha256"], code), count: 64) else { try fail(code) }
        guard
              try integer(entry["source_uid"], code) > 0,
              try integer(entry["source_gid"], code) > 0,
              try integer(entry["source_mode"], code) == 0o600,
              try integer(entry["source_nlink"], code) == 1,
              try integer(entry["source_size"], code) >= 0,
              Int(try string(entry["source_mtime_ns"], code)) != nil,
              UInt64(try string(entry["source_dev"], code)) != nil,
              UInt64(try string(entry["source_ino"], code)) != nil else { try fail("PUBLISHER1_SOURCE_AUTHORITY") }
        entries.append(entry)
    }
#if !CI3_SYNTHETIC_TEST
    let authorityLeaves = try array(materializerAuthority["receiver_leaves"], code)
    guard authorityLeaves.count == entries.count else { try fail("STOP_PRE_AUTHORITY") }
    for index in entries.indices {
        let leaf = try dictionary(authorityLeaves[index], "STOP_PRE_AUTHORITY")
        try exactKeys(leaf, [
            "dev", "gid", "identity_sha256", "ino", "mode", "mtime_ns", "nlink",
            "path_sha256", "role", "sha256", "size", "uid",
        ], "STOP_PRE_AUTHORITY")
        let entry = entries[index]
        guard try string(leaf["role"], code) == string(entry["role"], code),
              try string(leaf["path_sha256"], code) == string(entry["source_path_sha256"], code),
              try string(leaf["sha256"], code) == string(entry["source_sha256"], code),
              try integer(leaf["uid"], code) == integer(entry["source_uid"], code),
              try integer(leaf["gid"], code) == integer(entry["source_gid"], code),
              try integer(leaf["mode"], code) == integer(entry["source_mode"], code),
              try integer(leaf["nlink"], code) == integer(entry["source_nlink"], code),
              try integer(leaf["size"], code) == integer(entry["source_size"], code),
              try string(leaf["mtime_ns"], code) == string(entry["source_mtime_ns"], code),
              try string(leaf["dev"], code) == string(entry["source_dev"], code),
              try string(leaf["ino"], code) == string(entry["source_ino"], code),
              try string(leaf["identity_sha256"], code) == string(entry["source_identity_sha256"], code) else {
            try fail("STOP_PRE_AUTHORITY")
        }
    }
#endif
    let destinationChain = try openAbsoluteDirectoryChain(destinationParent, code: code)
    let stateChain = try openAbsoluteDirectoryChain(stateRoot, code: code)
    let receiverChain = try openAbsoluteDirectoryChain(receiverRoot, code: code)
    defer {
        for descriptor in receiverChain.reversed() { Darwin.close(descriptor) }
        for descriptor in stateChain.reversed() { Darwin.close(descriptor) }
        for descriptor in destinationChain.reversed() { Darwin.close(descriptor) }
    }
    let destinationParentFD = destinationChain.last!
    let stateFD = stateChain.last!
    let receiverFD = receiverChain.last!
    let destinationIdentity = physical(try fstatValue(destinationParentFD, code))
    let stateIdentity = physical(try fstatValue(stateFD, code))
    let receiverIdentity = physical(try fstatValue(receiverFD, code))
#if !CI3_SYNTHETIC_TEST
    guard try string(materializerAuthority["receiver_root_identity_sha256"], code) == physicalIdentityHash(receiverIdentity) else {
        try fail("STOP_PRE_AUTHORITY")
    }
#endif
    let requestHash = try sha256(input)
    let requestPathHash = try sha256(Data((requestPath ?? "CI3_SYNTHETIC_STDIN").utf8))
    let requestIdentityHash = try requestPhysical.map { try physicalIdentityHash($0) } ?? sha256(input)
    let claim: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_PUBLISHER1_TRANSACTION_CLAIM_V1",
        "authority_sha": authority, "remote_generation_id": remoteGeneration,
        "controller_generation_id": controllerGeneration, "receiver_manifest_sha256": receiverManifestHash,
        "request_sha256": requestHash, "request_path_sha256": requestPathHash,
        "request_identity_sha256": requestIdentityHash,
        "receiver_root_path_sha256": try sha256(Data(receiverRoot.utf8)),
        "receiver_root_identity_sha256": try physicalIdentityHash(receiverIdentity),
        "entries": entries.map { [
            "role": $0["role"]!, "sha256": $0["source_sha256"]!,
            "destination_relative_path": $0["destination_relative_path"]!, "mode": $0["mode"]!,
            "source_path_sha256": $0["source_path_sha256"]!,
            "source_uid": $0["source_uid"]!, "source_gid": $0["source_gid"]!,
            "source_mode": $0["source_mode"]!, "source_nlink": $0["source_nlink"]!,
            "source_size": $0["source_size"]!, "source_mtime_ns": $0["source_mtime_ns"]!,
            "source_dev": $0["source_dev"]!, "source_ino": $0["source_ino"]!,
            "source_identity_sha256": $0["source_identity_sha256"]!,
        ] }, "attempt": 1, "retry": false, "raw_values": false,
    ]
    let claimBytes = try compactJSONBytes(claim)
    var claimExists = false
    let claimFD = "publisher1.claim.json".withCString {
        Darwin.openat(stateFD, $0, O_RDONLY | O_NOFOLLOW)
    }
    if claimFD >= 0 {
        claimExists = true
        let existing = try readDescriptorBytes(claimFD, code)
        Darwin.close(claimFD)
        guard existing == claimBytes else { try fail("PUBLISHER1_DIVERGENT_CLAIM") }
    } else {
        guard errno == ENOENT else { try fail(code) }
    }
    let finalName = authority
    var finalStat = stat()
    let finalExists = finalName.withCString { Darwin.fstatat(destinationParentFD, $0, &finalStat, AT_SYMLINK_NOFOLLOW) } == 0
    if claimExists || finalExists {
        guard claimExists, finalExists, (finalStat.st_mode & S_IFMT) == S_IFDIR else { try fail("PUBLISHER1_CLAIM_CONSUMED_NO_RESULT") }
        let existingResultFD = "publisher1.result.json".withCString { Darwin.openat(stateFD, $0, O_RDONLY | O_NOFOLLOW) }
        if existingResultFD < 0 {
            guard errno == ENOENT else { try fail(code) }
            // A retained claim plus the exact promoted generation is the only
            // recoverable post-rename boundary.  Authenticate every leaf from
            // the claim, then finish freezing the destination without reading
            // receiver paths or repeating the install effect.
            try freezePublisher1PublishedTree(
                parentFD: destinationParentFD, finalName: finalName, entries: entries, code: code
            )
        }
        let observations = try observePublisher1Tree(parentFD: destinationParentFD, finalName: finalName, entries: entries, code: code)
        let result: [String: Any] = [
            "schema_version": 1, "purpose": "CI3_PUBLISHER1_TRANSACTION_RESULT_V1",
            "authority_sha": authority, "controller_generation_id": controllerGeneration,
            "claim_sha256": try sha256(claimBytes), "request_sha256": requestHash,
            "source_observations": entries.map { [
                "role": $0["role"]!, "source_path_sha256": $0["source_path_sha256"]!,
                "source_sha256": $0["source_sha256"]!,
                "source_uid": $0["source_uid"]!, "source_gid": $0["source_gid"]!,
                "source_mode": $0["source_mode"]!, "source_nlink": $0["source_nlink"]!,
                "source_size": $0["source_size"]!, "source_mtime_ns": $0["source_mtime_ns"]!,
                "source_dev": $0["source_dev"]!, "source_ino": $0["source_ino"]!,
                "source_identity_sha256": $0["source_identity_sha256"]!,
            ] },
            "observations": observations, "terminal_state": "PUBLISHED", "raw_values": false,
        ]
        let resultBytes = try compactJSONBytes(result)
        let status: String
        if existingResultFD >= 0 {
            let existing = try readDescriptorBytes(existingResultFD, code)
            Darwin.close(existingResultFD)
            guard existing == resultBytes else { try fail("PUBLISHER1_DIVERGENT_RESULT") }
            status = "EXISTS_VERIFIED"
        } else {
            guard errno == ENOENT else { try fail(code) }
            try writeExclusiveAt(stateFD, "publisher1.result.json", bytes: resultBytes, mode: 0o444, code: code)
            status = "EXISTS_RECOVERED"
        }
        print("PUBLISHER1_TRANSACTION PASS status=\(status) effect_executions=0")
        return
    }
    var sources: [(entry: [String: Any], descriptor: Int32, bytes: Data, physical: Physical)] = []
    defer { for source in sources { Darwin.close(source.descriptor) } }
    for entry in entries {
        let role = try string(entry["role"], code)
        let leaf = "\(role).payload"
        let descriptor = leaf.withCString { Darwin.openat(receiverFD, $0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { try fail(code) }
        let before = try fstatValue(descriptor, code)
        let bytes = try readDescriptorBytes(descriptor, code)
        let after = try fstatValue(descriptor, code)
        let observed = physical(after)
        guard physical(before) == observed, (after.st_mode & S_IFMT) == S_IFREG,
              observed.uid == UInt32(try integer(entry["source_uid"], code)),
              observed.gid == UInt32(try integer(entry["source_gid"], code)),
              observed.mode == UInt16(try integer(entry["source_mode"], code)),
              observed.nlink == UInt16(try integer(entry["source_nlink"], code)),
              observed.size == Int64(try integer(entry["source_size"], code)),
              observed.mtimeNS == (try string(entry["source_mtime_ns"], code)),
              observed.dev == (try string(entry["source_dev"], code)),
              observed.ino == (try string(entry["source_ino"], code)),
              try physicalIdentityHash(observed) == string(entry["source_identity_sha256"], code),
              try sha256(bytes) == string(entry["source_sha256"], code) else {
            Darwin.close(descriptor); try fail("PUBLISHER1_SOURCE_AUTHORITY")
        }
        sources.append((entry, descriptor, bytes, observed))
    }
#if !CI3_SYNTHETIC_TEST
    try validatePublisher1SemanticSources(
        sources, authority: authority, remoteGeneration: remoteGeneration,
        controllerGeneration: controllerGeneration, receiverManifestHash: receiverManifestHash,
        trustedIssuerBytes: trustedIssuerBytes
    )
#endif
#if CI3_SYNTHETIC_TEST
    if let role = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_PUBLISHER1_SWAP_SOURCE_ROLE"],
       entries.contains(where: { ($0["role"] as? String) == role }) {
        let original = (receiverRoot as NSString).appendingPathComponent("\(role).payload")
        let displaced = (receiverRoot as NSString).appendingPathComponent("\(role).payload.original")
        guard Darwin.rename(original, displaced) == 0 else { try fail("SYNTHETIC_SWAP") }
        try Data("untrusted-replacement\n".utf8).write(to: URL(fileURLWithPath: original), options: .withoutOverwriting)
        guard Darwin.chmod(original, 0o600) == 0 else { try fail("SYNTHETIC_SWAP") }
    }
#endif
    guard physical(try fstatValue(receiverFD, code)) == receiverIdentity else { try fail("PUBLISHER1_SOURCE_DRIFT") }
    for source in sources {
        let role = try string(source.entry["role"], code)
        let leaf = "\(role).payload"
        let currentDescriptorPhysical = physical(try fstatValue(source.descriptor, code))
        var relative = stat()
        guard currentDescriptorPhysical == source.physical,
              leaf.withCString({ Darwin.fstatat(receiverFD, $0, &relative, AT_SYMLINK_NOFOLLOW) }) == 0,
              physical(relative) == source.physical else { try fail("PUBLISHER1_SOURCE_DRIFT") }
    }
    // Validation and descriptor retention are pre-claim reads. The first
    // external effect is permitted only after this durable exclusive claim;
    // recovery never reopens/refetches receiver sources.
    try writeExclusiveAt(stateFD, "publisher1.claim.json", bytes: claimBytes, mode: 0o444, code: code)
    let stagingName = ".staging-\(controllerGeneration)"
    guard stagingName.withCString({ Darwin.mkdirat(destinationParentFD, $0, 0o700) }) == 0 else { try fail("PUBLISHER1_NO_CLOBBER") }
    let stagingFD = try openDirectoryAt(destinationParentFD, stagingName, create: false, code: code)
    defer { Darwin.close(stagingFD) }
    for source in sources {
        let relative = try string(source.entry["destination_relative_path"], code)
        let parts = relative.split(separator: "/").map(String.init)
        var currentFD = stagingFD
        var opened: [Int32] = []
        defer { for descriptor in opened.reversed() { Darwin.close(descriptor) } }
        for component in parts.dropLast() {
            let next = try openDirectoryAt(currentFD, component, create: true, code: code)
            opened.append(next)
            currentFD = next
        }
        try writeExclusiveAt(currentFD, parts.last!, bytes: source.bytes,
                             mode: mode_t(try integer(source.entry["mode"], code)),
                             makeImmutable: false, code: code)
    }
    guard Darwin.fsync(stagingFD) == 0, Darwin.fsync(destinationParentFD) == 0 else { try fail(code) }
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_PUBLISHER1_SWAP_DESTINATION"] == "1" {
        let displaced = destinationParent + ".original"
        guard Darwin.rename(destinationParent, displaced) == 0,
              Darwin.mkdir(destinationParent, 0o700) == 0 else { try fail("SYNTHETIC_SWAP") }
    }
#endif
    let currentDestination = physical(try lstatValue(destinationParent, "PUBLISHER1_DESTINATION_DRIFT"))
    guard sameDirectoryIdentity(physical(try fstatValue(destinationParentFD, code)), destinationIdentity),
          sameDirectoryIdentity(currentDestination, destinationIdentity),
          sameDirectoryIdentity(physical(try fstatValue(stateFD, code)), stateIdentity) else {
        try fail("PUBLISHER1_DESTINATION_DRIFT")
    }
    let promoted = stagingName.withCString { source in
        finalName.withCString { destination in
            Darwin.renameatx_np(destinationParentFD, source, destinationParentFD, destination, UInt32(RENAME_EXCL))
        }
    }
    guard promoted == 0, Darwin.fsync(destinationParentFD) == 0 else { try fail("PUBLISHER1_NO_CLOBBER") }
#if CI3_SYNTHETIC_TEST
    if ProcessInfo.processInfo.environment["CI3_SYNTHETIC_PUBLISHER1_CRASH_AFTER"] == "PROMOTION" {
        try fail("SYNTHETIC_CRASH")
    }
#endif
    try freezePublisher1PublishedTree(
        parentFD: destinationParentFD, finalName: finalName, entries: entries, code: code
    )
    let observations = try observePublisher1Tree(parentFD: destinationParentFD, finalName: finalName, entries: entries, code: code)
    let result: [String: Any] = [
        "schema_version": 1, "purpose": "CI3_PUBLISHER1_TRANSACTION_RESULT_V1",
        "authority_sha": authority, "controller_generation_id": controllerGeneration,
        "claim_sha256": try sha256(claimBytes), "request_sha256": requestHash,
        "source_observations": entries.map { [
            "role": $0["role"]!, "source_path_sha256": $0["source_path_sha256"]!,
            "source_sha256": $0["source_sha256"]!,
            "source_uid": $0["source_uid"]!, "source_gid": $0["source_gid"]!,
            "source_mode": $0["source_mode"]!, "source_nlink": $0["source_nlink"]!,
            "source_size": $0["source_size"]!, "source_mtime_ns": $0["source_mtime_ns"]!,
            "source_dev": $0["source_dev"]!, "source_ino": $0["source_ino"]!,
            "source_identity_sha256": $0["source_identity_sha256"]!,
        ] },
        "observations": observations, "terminal_state": "PUBLISHED", "raw_values": false,
    ]
    try writeExclusiveAt(stateFD, "publisher1.result.json", bytes: try compactJSONBytes(result), mode: 0o444, code: code)
    print("PUBLISHER1_TRANSACTION PASS status=CREATED effect_executions=1")
}

private func currentWriterValidationIdentity() throws -> (hash: String, identityHash: String, signatureHash: String) {
    let binaryStat = try lstatValue(CommandLine.arguments[0], "WRITER_BINARY")
    let (binaryBytes, binaryPhysical) = try readBoundFile(
        CommandLine.arguments[0], mode: UInt16(binaryStat.st_mode & 0o777), code: "WRITER_BINARY"
    )
    let binaryHash = try sha256(binaryBytes)
#if !CI3_SYNTHETIC_TEST
    guard binaryPhysical.uid == 0, binaryPhysical.gid == 0, binaryPhysical.mode == 0o555,
          (binaryPhysical.flags & UInt32(UF_IMMUTABLE)) != 0 else { try fail("WRITER_BINARY") }
#endif
    let binaryIdentityHash = try physicalIdentityHash(binaryPhysical)
#if CI3_SYNTHETIC_TEST
    let signatureHash = try sha256(Data("SYNTHETIC_TEST_BUILD".utf8))
#else
    let signatureProcess = Process()
    signatureProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    signatureProcess.arguments = ["-d", "-r-", CommandLine.arguments[0]]
    signatureProcess.environment = ["HOME": "/var/empty", "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin"]
    let signatureOutput = Pipe()
    let signatureError = Pipe()
    signatureProcess.standardOutput = signatureOutput
    signatureProcess.standardError = signatureError
    try signatureProcess.run()
    signatureProcess.waitUntilExit()
    let signatureBytes = (try signatureOutput.fileHandleForReading.readToEnd() ?? Data())
        + (try signatureError.fileHandleForReading.readToEnd() ?? Data())
    guard signatureProcess.terminationStatus == 0 else { try fail("WRITER_SIGNATURE") }
    let signatureHash = try sha256(signatureBytes)
#endif
    return (binaryHash, binaryIdentityHash, signatureHash)
}

private func validateManifestOnly(arguments: [String]) throws {
    guard arguments.count == 7, arguments[0] == "--validate-manifest" else { try fail("MODE_INVALID") }
    let manifestPath = arguments[1]
    let authority = arguments[2]
    let generationArguments = Array(arguments[3...6])
    guard manifestPath.hasPrefix("/"), !manifestPath.contains("/../"), isHex(authority, count: 40) else {
        try fail("MODE_INVALID")
    }
    let (manifestBytes, _) = try readBoundFile(manifestPath, code: "TERMINAL_MANIFEST")
    let manifest = try jsonObject(manifestBytes, "TERMINAL_MANIFEST")
    let writer = try currentWriterValidationIdentity()
    let (generations, evidence, scans, _) = try validateManifest(
        manifest, authority: authority, generations: generationArguments,
        binaryHash: writer.hash, signatureHash: writer.signatureHash
    )
    let runScansRole = "\(evidencePrefix("controller", "RUN_SCANS"))-result"
    let runScansEntry = try evidenceEntry(evidence, role: runScansRole, "TERMINAL_SEMANTICS")
    let contracts = try array(manifest["terminal_settlement_contracts"], "TERMINAL_SEMANTICS")
        .map { try dictionary($0, "TERMINAL_SEMANTICS") }
    let scanRoots = try scans.map { entry -> [String: Any] in
        ["id": try string(entry["id"], "TERMINAL_SEMANTICS"),
         "sha256": try string(entry["sha256"], "TERMINAL_SEMANTICS")]
    }
    let evidenceRoots = try evidence.map { entry -> [String: Any] in
        ["role": try string(entry["role"], "TERMINAL_SEMANTICS"),
         "sha256": try string(entry["sha256"], "TERMINAL_SEMANTICS")]
    }
    let externalAuthorityRoles = [
        "operation-authority-root", "vps-pass-root", "vps-issuer-authority-root",
        "human-authorization-root", "publisher-input-manifest-root",
        "ssh-trust-descriptor", "ssh-public-key", "ssh-public-key-fingerprint",
    ]
    let externalAuthorityRoots = try externalAuthorityRoles.map { role -> [String: Any] in
        let entry = try evidenceEntry(evidence, role: role, "TERMINAL_SEMANTICS")
        return ["role": role, "sha256": try string(entry["sha256"], "TERMINAL_SEMANTICS")]
    }
    let phaseTargetRoots = try controllerEvidencePhases.map { phase -> [String: Any] in
        let role = "\(evidencePrefix("controller", phase))-receipt"
        let (entry, _, phaseReceipt) = try evidenceObject(evidence, role: role, "TERMINAL_SEMANTICS")
        let observation = try dictionary(phaseReceipt["observation"], "TERMINAL_SEMANTICS")
        let targets = try array(observation["targets"], "TERMINAL_SEMANTICS")
            .map { try dictionary($0, "TERMINAL_SEMANTICS") }
        return [
            "phase": phase,
            "receipt_sha256": try string(entry["sha256"], "TERMINAL_SEMANTICS"),
            "targets_sha256": try sha256(compactJSONArrayBytes(targets)),
        ]
    }
    let semanticRoots: [String: Any] = [
        "authority_manifest_sha256": try string(manifest["authority_manifest_sha256"], "TERMINAL_SEMANTICS"),
        "bootstrap_claim_sha256": try string(manifest["bootstrap_claim_sha256"], "TERMINAL_SEMANTICS"),
        "claim_result_chain_sha256": try string(manifest["claim_result_chain_sha256"], "TERMINAL_SEMANTICS"),
        "remote_bundle_sha256": try string(manifest["remote_bundle_sha256"], "TERMINAL_SEMANTICS"),
        "local_bundle_sha256": try string(manifest["local_bundle_sha256"], "TERMINAL_SEMANTICS"),
        "ssh_provenance_sha256": try string(manifest["ssh_provenance_sha256"], "TERMINAL_SEMANTICS"),
        "simulator_gate_sha256": try string(manifest["simulator_gate_sha256"], "TERMINAL_SEMANTICS"),
        "simulator_install_sha256": try string(manifest["simulator_install_sha256"], "TERMINAL_SEMANTICS"),
        "evidence_chain_sha256": try sha256(try jsonBytes(["evidence": evidence, "scans": scans])),
        "external_authority_roots": externalAuthorityRoots,
        "phase_target_roots": phaseTargetRoots,
        "scan_receipts": scanRoots,
        "terminal_settlement_contracts_sha256": try sha256(compactJSONArrayBytes(contracts)),
    ]
    let receipt: [String: Any] = [
        "schema_version": 1,
        "purpose": "CI3_TERMINAL_SEMANTIC_VALIDATION_RECEIPT_V1",
        "authority_sha": authority,
        "generations": generations,
        "terminal_manifest_sha256": try sha256(manifestBytes),
        "writer_binary_sha256": writer.hash,
        "writer_signature_sha256": writer.signatureHash,
        "writer_executable_identity_sha256": writer.identityHash,
        "run_scans_result_sha256": try string(runScansEntry["sha256"], "TERMINAL_SEMANTICS"),
        "terminal_settlement_contracts": contracts,
        "terminal_settlement_contracts_sha256": try sha256(compactJSONArrayBytes(contracts)),
        "evidence_count": evidence.count,
        "evidence_roots": evidenceRoots,
        "evidence_roots_sha256": try sha256(compactJSONArrayBytes(evidenceRoots)),
        "evidence_roles_sha256": try sha256(Data(evidenceRoles.joined(separator: "\n").utf8)),
        "scan_receipt_count": scans.count,
        "scan_receipt_roots": scanRoots,
        "scan_receipt_roots_sha256": try sha256(compactJSONArrayBytes(scanRoots)),
        "semantic_roots": semanticRoots,
        "semantic_roots_sha256": try sha256(compactJSONBytes(semanticRoots)),
        "raw_values": false,
    ]
    FileHandle.standardOutput.write(try compactJSONBytes(receipt))
}

private func executeWrite(arguments: [String]) throws {
    if arguments.count == 7, arguments.first == "--write" {
        try fail("PRIVILEGED_AUTHORITY")
    }
    guard arguments.count == 8, arguments[0] == "--write" else { try fail("MODE_INVALID") }
    let manifestPath = arguments[1]
    let authorityReceiptPath = arguments[2]
    let authority = arguments[3]
    let generationArguments = Array(arguments[4...7])
    guard manifestPath.hasPrefix("/"), !manifestPath.contains("/../"),
          authorityReceiptPath.hasPrefix("/"), !authorityReceiptPath.contains("/../"),
          isHex(authority, count: 40) else { try fail("MODE_INVALID") }
    guard isGeneration(generationArguments[3], prefix: "terminal") else { try fail("GENERATION_MISMATCH") }
    let root = try anchorRoot()
    let terminalGeneration = generationArguments[3]
    let expectedAuthorityReceiptPath = (((root as NSString).appendingPathComponent(authority) as NSString)
        .appendingPathComponent(terminalGeneration) as NSString).appendingPathComponent("privileged-authority.receipt.json")
    guard authorityReceiptPath == expectedAuthorityReceiptPath else { try fail("PRIVILEGED_AUTHORITY") }
#if CI3_SYNTHETIC_TEST
    let (authorityReceiptBytes, _) = try readBoundFile(authorityReceiptPath, mode: 0o600, code: "PRIVILEGED_AUTHORITY")
#else
    let (authorityReceiptBytes, authorityPhysical) = try readBoundFile(authorityReceiptPath, mode: 0o444, code: "PRIVILEGED_AUTHORITY")
    guard authorityPhysical.uid == 0, authorityPhysical.gid == 0,
          (authorityPhysical.flags & UInt32(UF_IMMUTABLE)) != 0 else { try fail("PRIVILEGED_AUTHORITY") }
#endif
    let authorityReceipt = try jsonObject(authorityReceiptBytes, "PRIVILEGED_AUTHORITY")
    guard try string(authorityReceipt["terminal_manifest_path_sha256"], "PRIVILEGED_AUTHORITY") == sha256(Data(manifestPath.utf8)) else { try fail("MANIFEST_PATH") }
    let (manifestBytes, _) = try readBoundFile(manifestPath, code: "TERMINAL_MANIFEST")
    let manifestHash = try sha256(manifestBytes)
    let manifest = try jsonObject(manifestBytes, "TERMINAL_MANIFEST")
    let writer = try currentWriterValidationIdentity()
    let binaryHash = writer.hash
    let binaryIdentityHash = writer.identityHash
    let signatureHash = writer.signatureHash
    let (generations, evidence, scans, controllerJournalFrameBytes) = try validateManifest(
        manifest, authority: authority, generations: generationArguments,
        binaryHash: binaryHash, signatureHash: signatureHash
    )
    let sourceHash = try string(manifest["writer_source_sha256"], "TERMINAL_MANIFEST")
    guard try string(manifest["writer_authority_path_sha256"], "TERMINAL_MANIFEST") == sha256(Data(authorityReceiptPath.utf8)) else { try fail("PRIVILEGED_AUTHORITY") }
    let validatedTerminalGeneration = try string(generations["terminal"], "TERMINAL_MANIFEST")
    let anchorPath = ((((root as NSString).appendingPathComponent(authority) as NSString)
        .appendingPathComponent(validatedTerminalGeneration) as NSString).appendingPathComponent("pre-anchor.json"))
    let claimPath = ((manifestPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent("privileged-anchor.claim.json")
    let (claimBytes, _) = try readBoundFile(claimPath, code: "PRIVILEGED_CLAIM")
    let claim = try jsonObject(claimBytes, "PRIVILEGED_CLAIM")
    try validatePrivilegedClaim(claim, manifestHash: manifestHash, authority: authority, terminalGeneration: validatedTerminalGeneration, sourceHash: sourceHash, binaryHash: binaryHash, anchorPath: anchorPath)
    let claimHash = try sha256(claimBytes)
    try validatePrivilegedAuthority(
        authorityReceipt, receiptPath: authorityReceiptPath, manifestPath: manifestPath,
        manifestHash: manifestHash, claimHash: claimHash, anchorPath: anchorPath,
        authority: authority, terminalGeneration: validatedTerminalGeneration,
        sourceHash: sourceHash, binaryHash: binaryHash, binaryIdentityHash: binaryIdentityHash,
        signatureHash: signatureHash
    )
    let generationDirectory = try secureAnchorDirectories(root: root, authority: authority, terminalGeneration: validatedTerminalGeneration)
    let evidenceChainHash = try sha256(try jsonBytes(["evidence": evidence, "scans": scans]))
    let components = try dictionary(manifest["components"], "TERMINAL_MANIFEST")
    let externalAuthorityRoles = [
        "operation-authority-root", "vps-pass-root", "vps-issuer-authority-root",
        "human-authorization-root", "publisher-input-manifest-root",
        "ssh-trust-descriptor", "ssh-public-key", "ssh-public-key-fingerprint",
    ]
    let externalAuthorityRoots = try externalAuthorityRoles.map { role -> [String: Any] in
        let entry = try evidenceEntry(evidence, role: role, "TERMINAL_EXTERNAL_AUTHORITY")
        return ["role": role, "sha256": try string(entry["sha256"], "TERMINAL_EXTERNAL_AUTHORITY")]
    }
    let phaseTargetRoots = try controllerEvidencePhases.map { phase -> [String: Any] in
        let role = "\(evidencePrefix("controller", phase))-receipt"
        let (entry, _, receipt) = try evidenceObject(evidence, role: role, "TERMINAL_PHASE_TARGET")
        let observation = try dictionary(receipt["observation"], "TERMINAL_PHASE_TARGET")
        let targets = try array(observation["targets"], "TERMINAL_PHASE_TARGET").map { try dictionary($0, "TERMINAL_PHASE_TARGET") }
        return [
            "phase": phase,
            "receipt_sha256": try string(entry["sha256"], "TERMINAL_PHASE_TARGET"),
            "targets_sha256": try sha256(compactJSONArrayBytes(targets)),
        ]
    }
    let anchor: [String: Any] = [
        "schema_version": 1,
        "purpose": "CI3_PRE_TERMINAL_ANCHOR_V1",
        "authority_sha": authority,
        "authority_tree": try string(manifest["authority_tree"], "TERMINAL_MANIFEST"),
        "authority_manifest_sha256": try string(manifest["authority_manifest_sha256"], "TERMINAL_MANIFEST"),
        "components": components,
        "writer_source_sha256": sourceHash,
        "writer_binary_sha256": binaryHash,
        "writer_signature_sha256": try string(manifest["writer_signature_sha256"], "TERMINAL_MANIFEST"),
        "generations": generations,
        "bootstrap_claim_sha256": try string(manifest["bootstrap_claim_sha256"], "TERMINAL_MANIFEST"),
        "claim_result_chain_sha256": try string(manifest["claim_result_chain_sha256"], "TERMINAL_MANIFEST"),
        "remote_bundle_sha256": try string(manifest["remote_bundle_sha256"], "TERMINAL_MANIFEST"),
        "local_bundle_sha256": try string(manifest["local_bundle_sha256"], "TERMINAL_MANIFEST"),
        "ssh_provenance_sha256": try string(manifest["ssh_provenance_sha256"], "TERMINAL_MANIFEST"),
        "simulator_gate_sha256": try string(manifest["simulator_gate_sha256"], "TERMINAL_MANIFEST"),
        "simulator_install_sha256": try string(manifest["simulator_install_sha256"], "TERMINAL_MANIFEST"),
        "writer_authority_path_sha256": try string(manifest["writer_authority_path_sha256"], "TERMINAL_MANIFEST"),
        "privileged_claim_sha256": claimHash,
        "evidence_chain_sha256": evidenceChainHash,
        "external_authority_roots": externalAuthorityRoots,
        "external_authority_roots_sha256": try sha256(compactJSONArrayBytes(externalAuthorityRoots)),
        "phase_target_roots": phaseTargetRoots,
        "phase_target_roots_sha256": try sha256(compactJSONArrayBytes(phaseTargetRoots)),
        "scan_ids": scanIDs,
        "scan_receipts": scans.map { ["id": $0["id"]!, "sha256": $0["sha256"]!] },
        "terminal_settlement_contracts_sha256": try sha256(compactJSONArrayBytes(
            try array(manifest["terminal_settlement_contracts"], "TERMINAL_MANIFEST").map { try dictionary($0, "TERMINAL_MANIFEST") }
        )),
        "important_finding_ids": findingIDs,
        "terminal_state": "PENDING_VERIFICATION",
        "created_at_utc": try string(manifest["created_at_utc"], "TERMINAL_MANIFEST"),
        "raw_values": false,
        "secret_read": false,
        "privilege_mode": "MACOS_ROOT_SINGLE_ADMIN_PROMPT",
        "append_only": true,
        "no_clobber": true,
    ]
    let anchorBytes = try jsonBytes(anchor)
    let anchorStatus = try writeAnchor(
        anchorBytes, to: anchorPath, originalPrivilegedClaimSha256: claimHash
    )
    let settlementContracts = try array(manifest["terminal_settlement_contracts"], "TERMINAL_MANIFEST").map {
        try dictionary($0, "TERMINAL_MANIFEST")
    }
    var semanticEvidenceBytes = Data()
    for entry in evidence {
        if try string(entry["role"], "TERMINAL_FINAL_SCAN") == "writer-source" { continue }
        let metadata = try dictionary(entry["metadata"], "TERMINAL_FINAL_SCAN")
        let (bytes, _) = try readBoundFile(
            try string(entry["path"], "TERMINAL_FINAL_SCAN"), expected: metadata,
            mode: UInt16(try integer(metadata["mode"], "TERMINAL_FINAL_SCAN")), code: "TERMINAL_FINAL_SCAN"
        )
        semanticEvidenceBytes += bytes
    }
    let (transactionStatus, settlementHash) = try publishTerminalTransaction(
        generationDirectory: generationDirectory, preAnchorPath: anchorPath, preAnchorBytes: anchorBytes,
        authorityReceiptBytes: authorityReceiptBytes, authority: authority, generations: generations,
        components: try dictionary(manifest["components"], "TERMINAL_MANIFEST"),
        settlementContracts: settlementContracts, semanticEvidenceBytes: semanticEvidenceBytes,
        controllerJournalFrameBytes: controllerJournalFrameBytes,
        originalPrivilegedClaimSha256: claimHash
    )
    let status = anchorStatus == "CREATED" || transactionStatus == "CREATED" ? "CREATED" : "EXISTS_VERIFIED"
    print("WRITER_TRANSACTION PASS status=\(status) pre_anchor_sha256=\(try sha256(anchorBytes)) settlement_sha256=\(settlementHash)")
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        let environment = ProcessInfo.processInfo.environment
        let scenario = environment["CI3_SYNTHETIC_E2E_SCENARIO"]
        let scenarioHash = environment["CI3_SYNTHETIC_SCENARIO_SHA256"]
        guard (scenario == nil) == (scenarioHash == nil) else { try fail("SELF_TEST_SCENARIO") }
        if let scenario, let scenarioHash {
            let parts = scenario.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let phases = controllerEvidencePhases + terminalSettlementPhases
            let boundaries = ["before-claim", "after-claim", "after-effect", "after-receipt", "after-result", "after-event"]
            guard parts.count == 2, phases.contains(parts[0]), boundaries.contains(parts[1]),
                  try sha256(Data(scenario.utf8)) == scenarioHash else { try fail("SELF_TEST_SCENARIO") }
        }
        guard scanIDs.count == 6, findingIDs.count == 24,
              controllerEvidencePhases.count + terminalSettlementPhases.count == 10,
              try sha256(Data("synthetic".utf8)).count == 64 else { try fail("SELF_TEST") }
        print("WRITER_SELF_TEST PASS checks=5 network_calls=0 privilege_prompts=0 semantic_phases=10 scan_surfaces=6")
        return
    }
    if arguments.count == 3, arguments[0] == "--promote-directory" {
        try promoteDirectoryExclusive(arguments[1], arguments[2])
        return
    }
    if arguments == ["--descriptor-transaction"] {
        try descriptorRelativeTransaction()
        return
    }
#if CI3_SYNTHETIC_TEST
    if arguments.first == "--publisher1-transaction", [1, 3].contains(arguments.count) {
        try publisher1Transaction(arguments: Array(arguments.dropFirst()))
        return
    }
#else
    if arguments.first == "--publisher1-transaction", arguments.count == 3 {
        try publisher1Transaction(arguments: Array(arguments.dropFirst()))
        return
    }
#endif
#if CI3_DARWIN_PROMOTION_PROBE
    if arguments.count == 2, arguments.first == "--publisher1-promotion-probe" {
        try publisher1PromotionProbe(arguments[1])
        return
    }
#endif
    if arguments.first == "--settle" { try fail("MODE_INVALID") }
    if arguments.first == "--validate-manifest" {
        try validateManifestOnly(arguments: arguments)
        return
    }
    if arguments.first == "--write" {
        if ProcessInfo.processInfo.environment["CI3_TERMINAL_WORKER"] == "1" {
            try executeWrite(arguments: arguments)
        } else {
            try superviseTerminalWrite(arguments: arguments)
        }
        return
    }
    try executeWrite(arguments: arguments)
}

// A single root invocation remains alive as a transient supervisor while a
// same-binary spawned child performs the transaction. A worker crash can therefore be
// recovered by reopening the same no-clobber roots without a second launcher,
// osascript process or authorization prompt.  The supervisor is not installed,
// daemonized or persisted; if it dies, normal recovery can only observe and
// fail closed.
private func superviseTerminalWrite(arguments: [String]) throws {
    var recoveryAttempt = 0
    while true {
        let worker = Process()
        worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        worker.arguments = arguments
        var environment = [
            "HOME": "/var/empty", "LANG": "C", "LC_ALL": "C",
            "PATH": "/usr/bin:/bin", "CI3_TERMINAL_WORKER": "1",
        ]
#if CI3_SYNTHETIC_TEST
        for key in [
            "CI3_SYNTHETIC_ANCHOR_ROOT", "CI3_SYNTHETIC_E2E_SCENARIO",
            "CI3_SYNTHETIC_SCENARIO_SHA256", "CI3_SYNTHETIC_REAL_IMMUTABLE",
        ] {
            if let value = ProcessInfo.processInfo.environment[key] { environment[key] = value }
        }
        if recoveryAttempt == 0,
           let value = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_TERMINAL_CRASH_AFTER"] {
            environment["CI3_SYNTHETIC_TERMINAL_CRASH_AFTER"] = value
        }
        if recoveryAttempt == 0,
           let value = ProcessInfo.processInfo.environment["CI3_SYNTHETIC_WRITE_ANCHOR_CRASH_AFTER"] {
            environment["CI3_SYNTHETIC_WRITE_ANCHOR_CRASH_AFTER"] = value
        }
#endif
        worker.environment = environment
        worker.standardInput = FileHandle.nullDevice
        worker.standardOutput = FileHandle.standardOutput
        worker.standardError = FileHandle.standardError
        do { try worker.run() } catch { try fail("TERMINAL_WORKER") }
        worker.waitUntilExit()
        if worker.terminationReason == .exit && worker.terminationStatus == 0 { return }
        let recoverable = worker.terminationReason == .uncaughtSignal || worker.terminationStatus == 75
        if recoverable && recoveryAttempt == 0 {
            recoveryAttempt += 1
            continue
        }
        if worker.terminationReason == .uncaughtSignal {
            FileHandle.standardError.write(Data("ERROR TERMINAL_WORKER\n".utf8))
        }
        exit(1)
    }
}

@main
struct CI3TerminalAnchorWriter {
    static func main() {
        do {
            try run()
        } catch let failure as WriterFailure {
#if CI3_SYNTHETIC_TEST
            if failure.code == "SYNTHETIC_CRASH",
               ProcessInfo.processInfo.environment["CI3_TERMINAL_WORKER"] == "1",
               (ProcessInfo.processInfo.environment["CI3_SYNTHETIC_TERMINAL_CRASH_AFTER"] != nil
                || ProcessInfo.processInfo.environment["CI3_SYNTHETIC_WRITE_ANCHOR_CRASH_AFTER"] != nil) {
                exit(75)
            }
#endif
            FileHandle.standardError.write(Data("ERROR \(failure.code)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("ERROR UNEXPECTED\n".utf8))
            exit(1)
        }
    }
}
