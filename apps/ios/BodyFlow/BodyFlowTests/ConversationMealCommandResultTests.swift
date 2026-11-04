import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Closed factual saved packet and epoch-bound outbox ACK")
struct ConversationMealCommandResultTests {
    @Test func actualProjectorFixturesMatchFrozenCommandAndOptionalHistoricalVariants() throws {
        let root = try fixtures()
        let command = try fixtureCommand()
        #expect(command.inputHash == root["input_hash"] as? String)
        let cases = try #require(root["cases"] as? [[String: Any]])
        #expect(cases.count == 7)
        for item in cases {
            let payload = try #require(item["payload"] as? [String: Any])
            let packet = try decode(payload)
            #expect(packet.commandID == command.commandID.uuidString.lowercased())
            #expect(packet.inputHash == command.inputHash)
            #expect(packet.receipt.inputHash == command.inputHash)
            #expect(packet.receipt.providerKey == "conversation.meal/\(packet.ownerID)/\(packet.commandID)")
            #expect(packet.receipt.logIDs == ["30000000-0000-4000-8000-000000000001"])
            #expect((packet.feedback == nil) == (payload["feedback"] is NSNull))
        }
    }

    @Test("principal errors never acknowledge a command", arguments: [
        "schema", "status", "extra", "owner", "owner-case", "command", "hash", "epoch", "admitted", "admitted-year-zero", "missing-feedback", "missing-receipt", "receipt-schema", "receipt-extra", "receipt-owner", "receipt-command", "receipt-hash", "registration", "provider", "meal", "date", "timezone", "consumed", "consumed-before-admitted", "consumed-nanosecond-before", "log-id", "empty-logs", "duplicate-logs", "too-many-logs", "effect-version",
    ])
    func principalRefusals(_ attack: String) throws {
        var p = try payload()
        switch attack {
        case "schema": p["schema"] = "conversation.meal-command-result.v2"
        case "status": p["status"] = "queued"
        case "extra": p["raw_context"] = "private"
        case "owner": p["owner_id"] = "bad"
        case "owner-case": p["owner_id"] = "A0000000-0000-4000-8000-000000000001"
        case "command": p["command_id"] = "bad"
        case "hash": p["input_hash"] = "bad"
        case "epoch": p["epoch"] = "bad"
        case "admitted": p["admitted_at"] = "2026-11-03T25:00:00Z"
        case "admitted-year-zero": p["admitted_at"] = "0000-11-03T10:00:00Z"
        case "missing-feedback": p.removeValue(forKey: "feedback")
        case "missing-receipt": p.removeValue(forKey: "receipt")
        case "receipt-schema": try mutate(&p, ["receipt", "schema"], "conversation.meal-effect.v2")
        case "receipt-extra": try mutate(&p, ["receipt", "private_context"], "private")
        case "receipt-owner": try mutate(&p, ["receipt", "owner_id"], "10000000-0000-4000-8000-000000000002")
        case "receipt-command": try mutate(&p, ["receipt", "command_id"], "10000000-0000-4000-8000-000000000008")
        case "receipt-hash": try mutate(&p, ["receipt", "input_hash"], String(repeating: "f", count: 64))
        case "registration": try mutate(&p, ["receipt", "registration_id"], "bad")
        case "provider": try mutate(&p, ["receipt", "provider_key"], "legacy-provider")
        case "meal": try mutate(&p, ["receipt", "meal_type"], "unknown")
        case "date": try mutate(&p, ["receipt", "local_date"], "2026-11-04")
        case "timezone": try mutate(&p, ["receipt", "timezone"], "unresolved/zone")
        case "consumed": try mutate(&p, ["receipt", "consumed_at"], "1900-02-29T12:00:00Z")
        case "consumed-before-admitted": p["admitted_at"] = "2026-11-03T11:00:00.000001Z"
        case "consumed-nanosecond-before": p["admitted_at"] = "2026-11-03T11:00:00.000000002Z"; try mutate(&p, ["receipt", "consumed_at"], "2026-11-03T11:00:00.000000001Z")
        case "log-id": try mutate(&p, ["receipt", "log_ids"], ["bad"])
        case "empty-logs": try mutate(&p, ["receipt", "log_ids"], [] as [String])
        case "duplicate-logs": try mutate(&p, ["receipt", "log_ids"], Array(repeating: "30000000-0000-4000-8000-000000000001", count: 2))
        case "too-many-logs": try mutate(&p, ["receipt", "log_ids"], (0..<31).map { _ in UUID().uuidString.lowercased() })
        case "effect-version": try mutate(&p, ["receipt", "effect_version"], "cmeal1:not-a-hash")
        default: Issue.record("Unknown attack")
        }
        #expect(throws: (any Error).self) { try decode(p) }
    }

    @Test("optional feedback never invalidates factual saved result", arguments: ["null", "number", "schema", "original", "epoch", "command", "clock", "log", "meal", "raw-v2", "private", "oversize"])
    func optionalFailure(_ attack: String) throws {
        var p = try payload()
        switch attack {
        case "null": p["feedback"] = NSNull()
        case "number": p["feedback"] = 200
        case "schema": try mutate(&p, ["feedback", "schema"], "unknown")
        case "original": try mutate(&p, ["feedback", "original", "registration_id"], "20000000-0000-4000-8000-000000000002")
        case "epoch": try mutate(&p, ["feedback", "provenance", "epoch"], "50000000-0000-4000-8000-000000000002")
        case "command": try mutate(&p, ["feedback", "provenance", "command_id"], "10000000-0000-4000-8000-000000000008")
        case "clock": try mutate(&p, ["feedback", "provenance", "observed_at"], "2026-11-02T12:00:00Z"); try mutate(&p, ["feedback", "current_policy", "observed_at"], "2026-11-02T12:00:00Z")
        case "log": try mutate(&p, ["feedback", "recorded", "items", "0", "log_id"], "30000000-0000-4000-8000-000000000002")
        case "meal": try mutate(&p, ["feedback", "recorded", "meal_kind"], "jantar")
        case "raw-v2": p["feedback"] = ["schema": "registration.feedback.v2"]
        case "private": try mutate(&p, ["feedback", "private_health"], "private")
        case "oversize": try mutate(&p, ["feedback", "sections", "0", "text"], String(repeating: "x", count: 64_001))
        default: Issue.record("Unknown attack")
        }
        let result = try decode(p)
        #expect(result.feedback == nil)
        #expect(result.receipt.registrationID == "20000000-0000-4000-8000-000000000001")
    }

    @Test func actualPacketAcknowledgesOnlyOriginalTicketAndPublishesInsideVisibleGate() async throws {
        let f = try await fixture(); defer { f.disk.remove() }
        let ticket = try await f.session.prepareDispatch(commandID: f.command.commandID, server: f.server)
        let probe = await MainActor.run { SavedPacketProbe() }
        try await f.session.acknowledgeSaved(ticket: ticket, resultData: data(payload()), server: f.server) { probe.values.append($0) }
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
        #expect(await probe.values.count == 1)
        #expect(await probe.values.first?.receipt.registrationID == "20000000-0000-4000-8000-000000000001")
        #expect(await probe.values.first?.feedback?.scope.ownerID == f.lease.userID)
        await #expect(throws: ConversationOutboxError.commandNotFound) {
            try await f.session.acknowledgeSaved(ticket: ticket, resultData: data(payload()), server: f.server) { probe.values.append($0) }
        }
        #expect(await probe.values.count == 1)
        await f.session.invalidate()
    }

    @Test func restartAndNullFeedbackStillAcknowledgeRealFactualReceiptWithoutNewIntent() async throws {
        let f = try await fixture(); defer { f.disk.remove() }
        _ = try await f.session.prepareDispatch(commandID: f.command.commandID, server: f.server)
        await f.session.invalidate()
        let reopened = try await ConversationOutboxSession.open(lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
        let retry = try await reopened.reconciliationTicket(commandID: f.command.commandID)
        let probe = await MainActor.run { SavedPacketProbe() }
        var p = try payload(); p["feedback"] = NSNull()
        try await reopened.acknowledgeSaved(ticket: retry, resultData: data(p), server: f.server) { probe.values.append($0) }
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
        let published = await probe.values
        #expect(published.count == 1 && published.first?.feedback == nil)
        await reopened.invalidate()
    }

    @Test("mismatched packet or observation preserves exact ciphertext and produces no publication", arguments: ["owner", "command", "hash", "epoch", "observation", "meal", "http200"])
    func ackBindingRefusals(_ attack: String) async throws {
        let f = try await fixture(); defer { f.disk.remove() }
        let ticket = try await f.session.prepareDispatch(commandID: f.command.commandID, server: f.server)
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        let probe = await MainActor.run { SavedPacketProbe() }
        var p = try payload(), server = f.server
        switch attack {
        case "owner":
            let owner = "10000000-0000-4000-8000-000000000002"; p["owner_id"] = owner
            try mutate(&p, ["receipt", "owner_id"], owner); try mutate(&p, ["receipt", "provider_key"], "conversation.meal/\(owner)/\(ticket.commandID.uuidString.lowercased())")
        case "command":
            let command = "10000000-0000-4000-8000-000000000008"; p["command_id"] = command
            try mutate(&p, ["receipt", "command_id"], command); try mutate(&p, ["receipt", "provider_key"], "conversation.meal/\(f.lease.userID)/\(command)")
        case "hash": p["input_hash"] = String(repeating: "f", count: 64); try mutate(&p, ["receipt", "input_hash"], String(repeating: "f", count: 64))
        case "epoch": p["epoch"] = UUID().uuidString.lowercased()
        case "observation": server = .init(ownerID: f.server.ownerID, localSessionGeneration: f.server.localSessionGeneration, epoch: UUID())
        case "meal": try mutate(&p, ["receipt", "meal_type"], "jantar")
        case "http200": p = ["status": 200]
        default: Issue.record("Unknown attack")
        }
        let bytes = try data(p), observed = server
        await #expect(throws: (any Error).self) { try await f.session.acknowledgeSaved(ticket: ticket, resultData: bytes, server: observed) { probe.values.append($0) } }
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        #expect(await probe.values.isEmpty)
        await f.session.invalidate()
    }

    @Test func acknowledgementNeverDeletesAnotherIdenticalNewIntent() async throws {
        let f = try await fixture(); defer { f.disk.remove() }
        let other = try await f.session.enqueue(source: .text("leite integral 206 g"), mealType: .cafe, server: f.server)
        #expect(other != f.command.commandID)
        let ticket = try await f.session.prepareDispatch(commandID: f.command.commandID, server: f.server)
        try await f.session.acknowledgeSaved(ticket: ticket, resultData: data(payload()), server: f.server) { _ in }
        let remaining = try f.disk.store.load(owner: f.owner, key: f.disk.key)
        #expect(remaining.count == 1 && remaining[0].commandID == other)
        #expect(remaining[0].state == .queued && remaining[0].originalServerEpoch == f.server.epoch)
        await f.session.invalidate()
    }

    @Test func missingCiphertextCannotTurnAResultIntoBlindAcknowledgementOrNewWork() async throws {
        let f = try await fixture(); defer { f.disk.remove() }
        let ticket = try await f.session.prepareDispatch(commandID: f.command.commandID, server: f.server)
        try FileManager.default.removeItem(at: f.disk.store.fileURL(owner: f.owner)) // Task-owned synthetic fault only.
        await #expect(throws: ConversationOutboxError.commandNotFound) {
            try await f.session.acknowledgeSaved(ticket: ticket, resultData: data(payload()), server: f.server) { _ in Issue.record("Unexpected publication") }
        }
        #expect(!(try f.disk.store.containsCiphertext(owner: f.owner)))
        await f.session.invalidate()
    }

    @Test func consumedTimestampUsesReceiptTimezoneAndNanoseconds() throws {
        var p = try payload()
        p["admitted_at"] = "2026-11-04T00:30:00.000000001Z"
        try mutate(&p, ["receipt", "consumed_at"], "2026-11-03T21:30:00.000000001-03:00")
        try mutate(&p, ["receipt", "timezone"], "America/Sao_Paulo")
        let result = try decode(p)
        #expect(result.receipt.localDate == "2026-11-03")
        p["admitted_at"] = "2026-11-04T00:30:00.000000002Z"
        #expect(throws: (any Error).self) { try decode(p) }
    }

    @Test func permanentHoldAndForeignSessionTicketCannotBeAcknowledged() async throws {
        let f = try await fixture(); defer { f.disk.remove() }
        let ticket = try await f.session.prepareDispatch(commandID: f.command.commandID, server: f.server)
        try await f.session.markWaiting(ticket: ticket, hold: .reset)
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await f.session.acknowledgeSaved(ticket: ticket, resultData: data(payload()), server: f.server) { _ in Issue.record("Unexpected publication") } }
        let other = try await ConversationOutboxSession.open(lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
        await #expect(throws: ConversationOutboxError.invalidTransition) { try await other.acknowledgeSaved(ticket: ticket, resultData: data(payload()), server: f.server) { _ in Issue.record("Unexpected publication") } }
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        await f.session.invalidate(); await other.invalidate()
    }

    @Test func failedDeletionKeepsUnknownWorkAndAccountSwapAfterDeletionSuppressesPublication() async throws {
        let f = try await fixture(); defer { f.disk.remove() }
        let ticket = try await f.session.prepareDispatch(commandID: f.command.commandID, server: f.server)
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        let probe = await MainActor.run { SavedPacketProbe() }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: f.disk.store.root.path)
        await #expect(throws: ConversationOutboxError.storageUnavailable) { try await f.session.acknowledgeSaved(ticket: ticket, resultData: data(payload()), server: f.server) { probe.values.append($0) } }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.disk.store.root.path)
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        #expect(await probe.values.isEmpty)
        await f.lifecycle.replaceBeforeNextVisible(lease: .init(userID: "10000000-0000-4000-8000-000000000002", generation: 8, bearer: "synthetic-B"))
        await #expect(throws: (any Error).self) { try await f.session.acknowledgeSaved(ticket: ticket, resultData: data(payload()), server: f.server) { probe.values.append($0) } }
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
        #expect(await probe.values.isEmpty)
        await f.session.invalidate()
    }

    private struct Fixture {
        let disk: OutboxDiskFixture
        let lease: SessionLease
        let owner: ConversationOutboxOwner
        let lifecycle: OutboxLifecycleFake
        let vault: ConversationOutboxKeyVault
        let server: ConversationOutboxServerObservation
        let command: ConversationMealCommand
        let session: ConversationOutboxSession
    }
    private func fixture() async throws -> Fixture {
        let disk = try OutboxDiskFixture(), root = try fixtures(), command = try fixtureCommand()
        let lease = SessionLease(userID: try #require(root["owner_id"] as? String), generation: 7, bearer: "synthetic-only")
        let owner = try ConversationOutboxOwner(lease: lease), keychain = OutboxKeychainFake()
        await keychain.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
        let epochText = try #require(root["epoch"] as? String)
        let server = ConversationOutboxServerObservation(ownerID: try #require(UUID(uuidString: lease.userID)), localSessionGeneration: lease.generation, epoch: try #require(UUID(uuidString: epochText)))
        try disk.store.update(owner: owner, key: disk.key) { $0.append(.init(command: command, originalServerEpoch: server.epoch)) }
        let lifecycle = OutboxLifecycleFake(lease: lease), vault = ConversationOutboxKeyVault(service: "synthetic", security: keychain)
        let session = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: disk.store, keyVault: vault)
        return .init(disk: disk, lease: lease, owner: owner, lifecycle: lifecycle, vault: vault, server: server, command: command, session: session)
    }
    private func fixtures() throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let url = try #require(Bundle.module.url(forResource: "ConversationMealCommandResultFixtures", withExtension: "json"))
        #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/ConversationMealCommandResultFixtures.json")
        #endif
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func fixtureCommand() throws -> ConversationMealCommand { try ConversationMealCommand(wireBody: data(#require(fixtures()["wire_command"] as? [String: Any]))) }
    private func payload() throws -> [String: Any] { try #require((fixtures()["cases"] as? [[String: Any]])?.first?["payload"] as? [String: Any]) }
    private func decode(_ p: [String: Any]) throws -> SavedConversationMealCommandResultSnapshot { try JSONDecoder().decode(SavedConversationMealCommandResultSnapshot.self, from: data(p)) }
    private func data(_ p: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: p, options: [.sortedKeys, .withoutEscapingSlashes]) }
    private func mutate(_ value: inout [String: Any], _ path: [String], _ replacement: Any) throws {
        func changed(_ raw: Any, _ keys: ArraySlice<String>) throws -> Any {
            guard let key = keys.first else { return replacement }
            if var o = raw as? [String: Any] {
                if keys.count == 1 { o[key] = replacement } else { o[key] = try changed(try #require(o[key]), keys.dropFirst()) }
                return o
            }
            var a = try #require(raw as? [Any]); let i = try #require(Int(key)); a[i] = try changed(a[i], keys.dropFirst()); return a
        }
        value = try #require(changed(value, path[...]) as? [String: Any])
    }
}

@MainActor private final class SavedPacketProbe { var values: [ConversationOutboxSavedPublication] = [] }
